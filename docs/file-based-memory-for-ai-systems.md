# File-Based Memory for AI Systems: How Far Simple Persistence Actually Gets You

Most teams building agentic systems reach for vector databases the moment "memory" enters the conversation. This is backwards. The majority of AI memory problems are not retrieval problems -- they are persistence problems, and the file system solves persistence better than any database for most workloads. This document maps the full terrain of file-based memory: from a single JSON file through structured folder hierarchies through SQLite -- covering what works, what breaks, how multi-agent concurrency forces architectural decisions, and exactly where the file system stops being sufficient.

**Prerequisites:** [Memory and State Management](memory-and-state-management.md) (memory taxonomy, maturity levels, failure modes), [Context Engineering](context-engineering.md) (context budgeting, compaction strategies). This document operates at Levels 3-4 of the [memory maturity spectrum](memory-and-state-management.md#the-memory-maturity-spectrum) -- persistent external memory and structured typed operations -- and draws the precise boundary where Level 5 infrastructure becomes necessary.

| What teams assume | What actually happens |
|---|---|
| "We need a vector database for agent memory" | A JSON progress file solves 80% of memory complaints; [git commits solve another 15%](memory-and-state-management.md) |
| "Files are too simple for production" | Claude Code, Manus, Cursor, and Codex all ship file-based memory in production at scale |
| "More sophisticated storage = better recall" | [Filesystem search outperforms naive vector search](https://www.llamaindex.ai/blog/files-are-all-you-need) on collections under ~1,000 documents |
| "Files can't handle multiple agents" | Files handle multiple agents fine with coordination; the hard part is knowing when coordination cost exceeds the benefit |
| "SQLite is overkill for agent state" | SQLite is a single file with ACID guarantees, FTS5 search, and zero deployment overhead -- it is the natural ceiling of "simple" |
| "The switch to vector DBs is gradual" | The switch is a phase transition: below the threshold, files win on every axis; above it, they lose on retrieval quality catastrophically |

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c', 'edgeLabelBackground': '#1a202c', 'clusterBkg': '#1a202c', 'clusterBorder': '#4a5568'}}}%%
graph LR
    subgraph Simple["File-Based (This Document)"]
        A["Single JSON<br/>1 file, 1 agent"]
        B["Multi-File<br/>Typed markdown"]
        C["Folder Hierarchy<br/>Scoped + indexed"]
        D["SQLite + FTS5<br/>Structured queries"]
    end
    subgraph Complex["Database-Backed"]
        E["SQLite + Vectors<br/>Hybrid search"]
        F["Vector DB<br/>Semantic retrieval"]
        G["Knowledge Graph<br/>Relational memory"]
    end
    A --> B --> C --> D --> E --> F --> G
    style Simple fill:#1a202c,stroke:#4a5568,color:#e2e8f0
    style Complex fill:#2d3748,stroke:#4a5568,color:#e2e8f0
```

---

## The Core Tension

File-based memory works because LLMs already understand files. Every model can read JSON, parse markdown, and follow structured text. There is no impedance mismatch between how the agent thinks and how the data is stored. A progress file read into the context window is immediately actionable -- no embedding, no retrieval pipeline, no relevance scoring. The agent reads the file and knows exactly where it left off.

But file-based memory fails because **files have no query interface**. You can read a file. You can search a file with grep. You cannot ask a file "what do I know about authentication that is relevant to this user's current question about OAuth token refresh?" That question requires semantic understanding, and semantic understanding requires either (a) the agent reading every file and deciding in-context, which burns tokens and degrades attention, or (b) an external system that understands meaning, which is a vector database.

The entire design space of file-based memory exists in the tension between these two facts: **files are the highest-fidelity storage medium for LLMs, and files are the lowest-capability retrieval medium for LLMs.** Every approach in this document is a strategy for maximizing the first advantage while mitigating the second limitation.

The tension resolves differently depending on two variables: **corpus size** (how many memories exist) and **query type** (exact recall vs. semantic similarity). When you have fewer than ~1,000 discrete memories and your queries are exact ("what was the decision about the auth module?"), files win unconditionally. When you have 10,000+ memories and your queries are semantic ("what patterns have worked for similar authentication issues?"), files lose unconditionally. Everything in between is engineering judgment.

---

## Failure Taxonomy

These failures are specific to file-based memory systems. For the broader memory failure taxonomy (stale memories, irrelevant retrieval, context clash), see [Memory and State Management](memory-and-state-management.md#failure-taxonomy).

### Failure 1: The Monolithic File That Outgrows Its Context Budget

A team starts with a single `memory.json` containing user preferences, session history, and learned patterns. It works beautifully at 50 entries. At 500 entries, the file consumes 8,000 tokens -- roughly 6% of a 128K context window. At 5,000 entries, it consumes 80,000 tokens and the agent's attention on the actual task degrades catastrophically. One [documented case](https://dev.to/anajuliabit/the-memorymd-problem-why-local-files-fail-at-scale-58ae) grew a MEMORY.md file to 15,000 tokens containing 47 contradictory preferences, 89 "important" decisions, and 156 random notes. Monthly cost for including this in every request at 100 daily interactions with GPT-4 Turbo: $555/month. The file doubles in size by month six.

**Root cause:** No eviction policy. Files accumulate by default. Unlike databases, there is no TTL, no LRU cache, no automatic compaction. Every entry persists until a human or agent explicitly removes it.

### Failure 2: The Corrupted Write

An agent crashes mid-write to `progress.json`. The file now contains half a JSON object. The next session reads the file, fails to parse it, and either crashes or -- worse -- starts from scratch, losing all progress. This is not hypothetical. Any `write()` call that is interrupted by process termination, disk full, or power loss can produce a partial file. JSON is particularly fragile here: a missing closing brace makes the entire file unparseable.

**Root cause:** File writes are not atomic. `open() + write() + close()` is three separate operations. If the process dies between `write()` and `close()`, the file is corrupt. If the process dies during `write()`, the file contains partial data.

### Failure 3: The Concurrent Clobber

Two agents read `shared-state.json`, each modify their respective sections, and both write back the full file. The second write silently overwrites the first agent's changes. This is **last-write-wins**, and as the [O'Reilly multi-agent memory analysis](https://www.oreilly.com/radar/why-multi-agent-systems-need-memory-engineering/) puts it, "silent last-write-wins is almost never correct -- it corrupts shared truth invisibly." In multi-agent systems, interagent misalignment from this pattern accounts for 36.9% of all failures.

**Root cause:** Files have no built-in concurrency control. There is no transaction, no compare-and-swap, no optimistic locking. Two processes can read the same file simultaneously, and neither knows the other exists.

### Failure 4: The Needle-in-a-Haystack Retrieval

An agent needs to recall a decision made three weeks ago about database indexing strategy. The decision is in `memory/2026-03-01.md`, buried on line 47 between a note about lunch preferences and a reminder to update dependencies. The agent either (a) loads all memory files into context, burning tokens on irrelevant content, or (b) uses grep to search for "indexing," which fails because the note says "we decided to add a composite key on user_id and created_at" without ever using the word "indexing."

**Root cause:** File-based retrieval is either exact-match (grep) or exhaustive (load everything). There is no middle ground. Semantic retrieval -- finding content by meaning rather than keywords -- requires embeddings, which requires infrastructure beyond the file system.

### Failure 5: The Schema Drift

Month one: `progress.json` has `{completed_steps: [], next_step: ""}`. Month three: someone adds `blocked_items`. Month five: `next_step` becomes `next_steps` (plural) in some files but not others. Month eight: a new agent writes `status` instead of `next_step`. No file enforces a schema. No migration runs. The agent encounters four different formats across its memory files and either halts on parse errors or silently ignores fields it does not recognize.

**Root cause:** Files are schemaless by default. JSON Schema validation must be added explicitly, and most teams skip it because "it's just a config file." By the time schema drift causes failures, dozens of inconsistent files exist.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c', 'edgeLabelBackground': '#2d3748', 'clusterBkg': '#2d3748', 'clusterBorder': '#4a5568'}}}%%
graph TD
    subgraph Failures["File-Based Memory Failure Modes"]
        F1["Monolithic Bloat<br/>No eviction, linear growth"]
        F2["Corrupted Write<br/>Non-atomic file operations"]
        F3["Concurrent Clobber<br/>Last-write-wins data loss"]
        F4["Needle in Haystack<br/>No semantic retrieval"]
        F5["Schema Drift<br/>No format enforcement"]
    end
    F1 -->|"drives"| F4
    F3 -->|"causes"| F2
    F5 -->|"amplifies"| F4
    style Failures fill:#2d3748,stroke:#4a5568,color:#e2e8f0
```

---

## The File-Based Memory Spectrum

Each level adds capability and complexity. The progression is not optional -- skipping levels produces systems that are overengineered for small workloads or underengineered for large ones.

### Level 1: Single JSON File

**What it is:** One file (`progress.json`, `state.json`, `memory.json`) containing all agent state. Read at session start, written at session end or after each significant step.

**When it works:** Single-agent systems with fewer than ~100 discrete state entries. Short-lived tasks (hours, not weeks). Situations where the entire state fits comfortably in the context window (<4,000 tokens).

**Canonical example:** Anthropic's [progress file pattern](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) for long-running agents:

```json
{
  "task": "Migrate user table from MySQL to PostgreSQL",
  "completed_steps": [
    "Analyzed source schema (14 tables, 3 views)",
    "Created target schema with type mappings",
    "Migrated users table (2.3M rows)"
  ],
  "current_step": "Migrate orders table",
  "decisions_made": [
    "Using BIGINT for IDs instead of UUID (performance)",
    "Preserving created_at timestamps, regenerating updated_at"
  ],
  "blocked_items": [],
  "files_modified": ["schema.sql", "migrate.py"]
}
```

**Strengths:** Zero infrastructure. Human-readable. Git-trackable. The agent reads it and knows exactly where it left off. Perfect precision and recall -- every entry is loaded, nothing is missed.

**Weaknesses:** No query capability beyond loading the entire file. No concurrency safety. No schema enforcement. Linear growth with no eviction. Becomes a context-window tax as it grows.

**Production examples:** Claude Code's `~/.claude/projects/<hash>/memory/MEMORY.md` (hard-capped at 200 lines). Manus's `task_plan.md`. Any `progress.json` checkpoint file.

### Level 2: Multi-File Typed Storage

**What it is:** Multiple files, each serving a specific purpose. Instead of one monolithic file, state is split by type: `preferences.json`, `decisions.md`, `progress.json`, `lessons-learned.md`.

**When it works:** Single-agent or orchestrator-mediated multi-agent systems. Corpus of 100-500 discrete entries across all files. Each individual file stays under ~2,000 tokens.

**Canonical example:** The three-layer pattern used by [Claude Code practitioners](https://ianlpaterson.com/blog/claude-code-memory-architecture/):

```
~/.claude/
  CLAUDE.md              # Layer 1: Global preferences (<60 lines)
project/
  CLAUDE.md              # Layer 2: Project conventions (git-versioned)
  .claude/rules/
    testing.md           # Modular rule: testing standards
    api-patterns.md      # Modular rule: API conventions
  .claude/memory/
    MEMORY.md            # Layer 3: Auto-generated learnings (200-line cap)
```

**Strengths:** Each file has a clear purpose. The agent loads only the files relevant to the current task. Modular rules in individual files achieve [96% compliance](https://institute.sfeir.com/en/claude-code/claude-code-memory-system-claude-md/deep-dive/) -- the highest measured rate. Git diffs are clean because changes are scoped to specific files.

**Weaknesses:** The agent must know which files to load. No automatic discovery -- if you add `security-rules.md` but do not tell the agent about it, it will never read it. File proliferation creates its own management burden. Cross-file references (e.g., a decision in `decisions.md` that relates to a preference in `preferences.md`) are invisible without explicit linking.

**Key finding:** Files under 200 lines achieve 92% rule compliance. Files over 400 lines drop to [71%](https://institute.sfeir.com/en/claude-code/claude-code-memory-system-claude-md/deep-dive/). This is not a soft guideline -- it is a measured performance cliff. The mechanism is attention degradation: as file length increases, the model's ability to attend to all instructions decreases non-linearly.

### Level 3: Folder Hierarchy with Index

**What it is:** A directory structure where files are organized by scope, topic, or time period, with an index file that maps topics to file paths.

**When it works:** 500-2,000 entries. Multiple agents that need scoped access (each agent reads only its relevant subdirectory). Long-running projects where temporal organization matters.

**Canonical example:** OpenClaw's [memory architecture](https://dev.to/imaginex/ai-agent-memory-management-when-markdown-files-are-all-you-need-5ekk):

```
~/.openclaw/memory/
  MEMORY.md                    # Index: topic -> file path
  decisions/
    2026-03-auth-strategy.md
    2026-03-database-choice.md
  patterns/
    error-handling.md
    api-pagination.md
  sessions/
    2026-03-22.md
    2026-03-21.md
```

With `MEMORY.md` serving as an index:

```markdown
## Decisions
- [Auth strategy](decisions/2026-03-auth-strategy.md) - OAuth2 with PKCE
- [Database choice](decisions/2026-03-database-choice.md) - PostgreSQL over MySQL

## Patterns
- [Error handling](patterns/error-handling.md) - Structured error types
- [API pagination](patterns/api-pagination.md) - Cursor-based
```

**Strengths:** The index file is small enough to always fit in context. The agent reads the index, identifies relevant files, and loads only those. Scoping by directory provides natural access control for multi-agent systems. Temporal organization enables "forget everything before March" by deleting a directory.

**Weaknesses:** The index must be maintained. If a file is added without updating the index, it is invisible. Directory structure decisions are architectural choices that are painful to change later. ripgrep/grep across the hierarchy works but becomes slow above ~1,000 files on spinning disks (negligible on SSDs).

**The discovery problem:** At this level, the agent needs a strategy for finding relevant files. Three approaches, in order of sophistication:

1. **Index-first:** Read `MEMORY.md`, follow links. Fast, precise, misses unindexed files.
2. **Glob + grep:** Search `memory/**/*.md` for keywords. Catches unindexed files, fails on synonym/paraphrase queries.
3. **Agent-directed search:** The agent decides which directories to search based on the task context. Most flexible, burns tokens on the search process itself.

### Level 4: SQLite with Full-Text Search

**What it is:** A single `.sqlite` file containing structured tables with FTS5 (Full-Text Search 5) virtual tables for keyword retrieval. No server. No deployment. One file that provides ACID transactions, schema enforcement, and indexed search.

**When it works:** 1,000-10,000 entries. Multi-agent systems that need concurrency safety. Workloads that require filtered queries ("show me all decisions tagged 'security' from the last 30 days"). Systems that need auditability.

**Canonical example:** A minimal agent memory schema:

```sql
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    memory_type TEXT CHECK(memory_type IN ('fact', 'decision', 'preference', 'pattern', 'task')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed DATETIME,
    access_count INTEGER DEFAULT 0,
    confidence REAL DEFAULT 1.0,
    source_session TEXT,
    tags TEXT,  -- comma-separated
    superseded_by TEXT REFERENCES memories(id)
);

CREATE VIRTUAL TABLE memories_fts USING fts5(content, tags, tokenize='porter');

CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content, tags) VALUES (new.rowid, new.content, new.tags);
END;
```

Query by keyword with ranking:

```sql
SELECT m.*, rank
FROM memories_fts f
JOIN memories m ON m.rowid = f.rowid
WHERE memories_fts MATCH 'authentication AND token'
  AND m.superseded_by IS NULL
  AND m.confidence > 0.5
ORDER BY rank
LIMIT 10;
```

**Strengths:** ACID transactions eliminate corrupted writes and concurrent clobber failures. FTS5 provides stemming, phrase matching, and BM25 ranking -- as one [practitioner noted](https://muhammadraza.me/2026/building-local-memory-for-coding-agents/), "for most use cases, this is all you need." Schema enforcement prevents drift. A single `.sqlite` file is as portable as a JSON file. Query latency is ~42ms at p50 for typical workloads ([STELE benchmarks](https://www.reddit.com/r/LLMDevs/comments/1r8zq5c/looking_for_early_testerscollaborators_stele_a/)). The `superseded_by` field solves stale memory through explicit versioning.

**Weaknesses:** LLMs cannot read `.sqlite` files directly -- you need a tool or wrapper that queries the database and returns results as text. This adds a layer of indirection that files do not have. SQLite's write concurrency is limited: one writer at a time (readers are unlimited with WAL mode). Complex queries require SQL knowledge that not all teams have.

**The critical upgrade path:** FTS5 handles stemming ("authenticate" matches "authentication") and phrase proximity, but it does not handle semantic similarity ("login flow" does not match "authentication process"). When your queries start requiring synonym and paraphrase matching, FTS5 hits its ceiling and you need embeddings.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c', 'edgeLabelBackground': '#1a202c', 'clusterBkg': '#1a202c', 'clusterBorder': '#4a5568'}}}%%
graph TD
    subgraph Levels["File-Based Memory Spectrum"]
        L1["Level 1: Single JSON<br/>0-100 entries<br/>1 agent, short tasks"]
        L2["Level 2: Multi-File<br/>100-500 entries<br/>1 agent, typed storage"]
        L3["Level 3: Folder Hierarchy<br/>500-2,000 entries<br/>Scoped access, indexed"]
        L4["Level 4: SQLite + FTS5<br/>1,000-10,000 entries<br/>ACID, full-text search"]
    end
    L1 -->|"file bloat<br/>forces split"| L2
    L2 -->|"discovery problem<br/>forces index"| L3
    L3 -->|"concurrency +<br/>query needs"| L4
    L4 -->|"semantic queries<br/>force embeddings"| VDB["Vector Database<br/>Beyond file-based"]
    style Levels fill:#1a202c,stroke:#4a5568,color:#e2e8f0
    style VDB fill:#2d3748,stroke:#4a5568,color:#e2e8f0
```

---

## Multi-Agent Concurrency: The Forcing Function

Concurrency is where file-based memory either scales or collapses. A single agent reading and writing its own files has no concurrency problem. The moment a second agent enters the picture, every file becomes a potential conflict zone.

### The Problem Space

Two agents working on the same codebase need shared state: "Which files have been modified?" "What decisions have been made?" "What is the current task status?" If both agents maintain their own separate state files, they diverge. If they share a state file, they conflict. There is no architecture that avoids this fundamental tension -- only architectures that manage it at different costs.

The [O'Reilly analysis](https://www.oreilly.com/radar/why-multi-agent-systems-need-memory-engineering/) quantifies the cost: multi-agent systems use ~15x the tokens of single-agent systems, primarily due to coordination overhead -- agents re-retrieving and re-explaining context that should be shared state. Without proper memory coordination, each agent operates in its own reality, and the realities drift.

### Strategy 1: Scoped Isolation (No Sharing)

Each agent gets its own directory. No shared state. The orchestrator reads each agent's output files and synthesizes.

```
memory/
  agent-researcher/
    findings.md
    progress.json
  agent-implementer/
    changes.md
    progress.json
  orchestrator/
    synthesis.md      # Orchestrator reads all agent dirs
```

**When it works:** MapReduce-style workflows where agents operate on disjoint inputs and produce independent outputs. The orchestrator is the only entity that needs a global view.

**When it fails:** Any workflow where agents need to react to each other's progress. Agent B needs to know that Agent A already modified `auth.py` before it makes its own changes to the same file.

**Concurrency cost:** Zero. No shared state means no conflicts. But also no coordination -- agents may duplicate work or produce contradictory outputs.

### Strategy 2: Orchestrator-Mediated Writes

Agents read shared state files but never write to them directly. All writes go through the orchestrator, which serializes updates.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c', 'edgeLabelBackground': '#2d3748', 'clusterBkg': '#2d3748', 'clusterBorder': '#4a5568'}}}%%
sequenceDiagram
    participant A as Agent A
    participant O as Orchestrator
    participant S as shared-state.json
    participant B as Agent B
    A->>O: "Completed auth module analysis"
    O->>S: Atomic write (read-modify-write)
    B->>O: "Need current state"
    O->>S: Read
    S-->>O: Current state
    O-->>B: State snapshot
    B->>O: "Implemented login endpoint"
    O->>S: Atomic write (read-modify-write)
```

**When it works:** Star-topology multi-agent systems where the orchestrator is always available and the write rate is low (fewer than ~10 writes per minute).

**When it fails:** When the orchestrator becomes a bottleneck. If agents produce results faster than the orchestrator can serialize writes, the queue backs up and agents stall waiting for acknowledgment. Also fails if the orchestrator crashes -- all in-flight writes are lost.

**Implementation pattern -- atomic file writes:**

```python
import json
import os
import tempfile

def atomic_write(filepath: str, data: dict) -> None:
    """Write data to file atomically using rename.

    The rename operation is atomic on POSIX systems when source
    and destination are on the same filesystem.
    """
    dir_name = os.path.dirname(filepath)
    with tempfile.NamedTemporaryFile(
        mode='w', dir=dir_name, suffix='.tmp', delete=False
    ) as tmp:
        json.dump(data, tmp, indent=2)
        tmp.flush()
        os.fsync(tmp.fileno())  # Force write to disk
    os.rename(tmp.name, filepath)  # Atomic on same filesystem
```

This eliminates Failure 2 (corrupted writes) but does not solve Failure 3 (concurrent clobber). The orchestrator must ensure only one write happens at a time.

### Strategy 3: File Locking

Agents acquire locks before writing to shared files. Two variants:

**Pessimistic locking** -- acquire a lock before reading, hold it through the write:

```python
import fcntl

def locked_update(filepath: str, update_fn):
    """Read-modify-write with exclusive file lock."""
    with open(filepath, 'r+') as f:
        fcntl.flock(f, fcntl.LOCK_EX)  # Block until lock acquired
        try:
            data = json.load(f)
            data = update_fn(data)
            f.seek(0)
            f.truncate()
            json.dump(data, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
```

**Optimistic locking** -- read freely, check version on write, retry on conflict:

```python
def optimistic_update(filepath: str, update_fn, max_retries=3):
    """Read-modify-write with version check and retry."""
    for attempt in range(max_retries):
        data = json.loads(Path(filepath).read_text())
        version = data.get("_version", 0)
        updated = update_fn(data)
        updated["_version"] = version + 1
        # Only write if version hasn't changed
        current = json.loads(Path(filepath).read_text())
        if current.get("_version", 0) == version:
            atomic_write(filepath, updated)
            return updated
    raise ConflictError(f"Failed after {max_retries} retries")
```

**When pessimistic wins:** Short-duration operations where lock contention is rare. Agents that read-modify-write in milliseconds.

**When optimistic wins:** Longer operations where holding a lock would block other agents. Agents that spend seconds or minutes between read and write (typical for LLM-powered agents, where the "modify" step involves an API call that takes 2-30 seconds).

**When both fail:** Distributed systems. `fcntl.flock()` only works on a single machine. Network filesystems (NFS, SMB) have notoriously unreliable locking semantics. If your agents run on different machines, file locking is not a viable strategy -- use a coordination service or a database.

### Strategy 4: SQLite as Coordination Layer

SQLite with WAL (Write-Ahead Logging) mode supports unlimited concurrent readers and serialized writers. This is the natural ceiling of file-based concurrency.

```python
import sqlite3

def get_connection(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")      # Enable concurrent reads
    conn.execute("PRAGMA busy_timeout=5000")      # Wait up to 5s for locks
    conn.execute("PRAGMA synchronous=NORMAL")     # Balance durability/speed
    return conn

def update_shared_state(db_path: str, agent_id: str, key: str, value: str):
    """Thread-safe state update with automatic retry on lock contention."""
    conn = get_connection(db_path)
    with conn:  # Automatic transaction
        conn.execute(
            """INSERT INTO shared_state (agent_id, key, value, updated_at)
               VALUES (?, ?, ?, CURRENT_TIMESTAMP)
               ON CONFLICT(key) DO UPDATE SET
                 value = excluded.value,
                 agent_id = excluded.agent_id,
                 updated_at = CURRENT_TIMESTAMP""",
            (agent_id, key, value)
        )
```

**When it works:** All single-machine multi-agent scenarios. Write rates up to ~100 writes/second (SQLite's serialized writer is fast -- the bottleneck is fsync, not the lock).

**When it fails:** Multiple machines. SQLite does not support network access. If agents run on different hosts, you need PostgreSQL, Redis, or a purpose-built coordination service.

### The Concurrency Decision Tree

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c', 'edgeLabelBackground': '#2d3748', 'clusterBkg': '#2d3748', 'clusterBorder': '#4a5568'}}}%%
graph TD
    Q1{"How many agents<br/>write to shared state?"}
    Q1 -->|"1"| A1["Single JSON file<br/>No coordination needed"]
    Q1 -->|"2-5"| Q2{"Same machine?"}
    Q1 -->|"5+"| Q3["SQLite with WAL<br/>or dedicated database"]
    Q2 -->|"Yes"| Q4{"Write frequency?"}
    Q2 -->|"No"| Q5["Database required<br/>Files cannot help here"]
    Q4 -->|"< 1/min"| A2["Orchestrator-mediated<br/>atomic writes"]
    Q4 -->|"1-10/min"| A3["File locking<br/>(optimistic preferred)"]
    Q4 -->|"> 10/min"| Q3
    style Q1 fill:#2d3748,stroke:#4a5568,color:#e2e8f0
    style Q2 fill:#2d3748,stroke:#4a5568,color:#e2e8f0
    style Q3 fill:#2d3748,stroke:#4a5568,color:#e2e8f0
    style Q4 fill:#2d3748,stroke:#4a5568,color:#e2e8f0
    style Q5 fill:#2d3748,stroke:#4a5568,color:#e2e8f0
    style A1 fill:#1a202c,stroke:#4a5568,color:#e2e8f0
    style A2 fill:#1a202c,stroke:#4a5568,color:#e2e8f0
    style A3 fill:#1a202c,stroke:#4a5568,color:#e2e8f0
```

---

## Principles for File-Based Memory Systems

### Principle 1: Enforce Size Caps Mechanically, Not Culturally

**Why it works:** Every file-based memory system that grows without bounds eventually hits Failure 1 (monolithic bloat). Telling developers "keep it short" does not work. Claude Code enforces a 200-line hard cap on MEMORY.md, and [measured compliance](https://institute.sfeir.com/en/claude-code/claude-code-memory-system-claude-md/deep-dive/) drops from 92% to 71% when files exceed 400 lines. The mechanism is attention degradation in the model, not human carelessness.

**How to apply:** Set an explicit token budget for memory files loaded into context. For a 128K context window, allocate no more than 2-3% (2,500-3,800 tokens, roughly 150-250 lines of markdown) to memory. Implement automated rotation:

```python
MAX_MEMORY_LINES = 200

def rotate_memory(memory_path: str, archive_dir: str):
    """Archive old entries when memory file exceeds cap."""
    lines = Path(memory_path).read_text().splitlines()
    if len(lines) <= MAX_MEMORY_LINES:
        return
    # Keep the most recent entries, archive the rest
    keep = lines[-MAX_MEMORY_LINES:]
    archive = lines[:-MAX_MEMORY_LINES]
    archive_path = Path(archive_dir) / f"{date.today().isoformat()}.md"
    archive_path.write_text("\n".join(archive))
    Path(memory_path).write_text("\n".join(keep))
```

**Addresses:** Failure 1 (monolithic bloat), Failure 4 (needle-in-haystack).

### Principle 2: Use Atomic Writes for Every State Mutation

**Why it works:** Non-atomic writes are the root cause of Failure 2 (corrupted files). The `write-to-temp-then-rename` pattern is the standard solution because `rename()` is atomic on POSIX filesystems when source and destination are on the same filesystem. This is not a best practice -- it is a correctness requirement. Any system that writes state to a file without atomic rename will eventually lose data.

**How to apply:** Never write directly to the target file. Always write to a temporary file in the same directory, fsync, then rename. The `atomic_write()` function shown in the concurrency section is the minimal correct implementation. Wrap it in your file I/O abstraction so that no code path can bypass it.

**Addresses:** Failure 2 (corrupted writes).

### Principle 3: Separate the Index from the Content

**Why it works:** At Level 2+, the agent must decide which files to load. Loading all files burns context budget on irrelevant content (Failure 4). An index file solves this by providing a small, always-loaded map from topics to file paths. The agent reads the index (<200 lines), identifies relevant files, and loads only those. This is the file-system equivalent of a database index -- it trades one small file read for many unnecessary large file reads.

**How to apply:** Maintain a `MEMORY.md` or `INDEX.md` at the root of your memory hierarchy. Each entry should have: topic, one-line description, file path. Keep the index under 200 lines. When adding a new memory file, update the index in the same operation. When deleting or archiving a memory file, remove its index entry. The index is the source of truth for what exists -- if it is not in the index, the agent will not find it.

```markdown
## Index

- [Auth strategy](decisions/auth-strategy.md) - OAuth2 with PKCE, decided 2026-03-01
- [Error handling](patterns/error-handling.md) - Structured error types with codes
- [DB migration plan](tasks/db-migration.md) - MySQL to PostgreSQL, 60% complete
```

**Addresses:** Failure 4 (needle-in-haystack), Failure 1 (bloat -- the index stays small even as content grows).

### Principle 4: Add Schema Validation at the Write Boundary

**Why it works:** Schema drift (Failure 5) compounds over time and is expensive to fix retroactively. Validating at write time -- not read time -- catches errors when they are cheapest to fix. The agent that writes a malformed entry gets immediate feedback; the agent that reads a malformed entry three weeks later has no recourse.

**How to apply:** For JSON files, use JSON Schema validation on every write:

```python
from jsonschema import validate

PROGRESS_SCHEMA = {
    "type": "object",
    "required": ["task", "completed_steps", "current_step"],
    "properties": {
        "task": {"type": "string"},
        "completed_steps": {"type": "array", "items": {"type": "string"}},
        "current_step": {"type": "string"},
        "decisions_made": {"type": "array", "items": {"type": "string"}},
        "blocked_items": {"type": "array", "items": {"type": "string"}},
        "_version": {"type": "integer"}
    }
}

def write_progress(filepath: str, data: dict):
    validate(instance=data, schema=PROGRESS_SCHEMA)
    atomic_write(filepath, data)
```

For markdown files, use YAML frontmatter with required fields:

```markdown
---
type: decision
date: 2026-03-22
status: active
supersedes: null
tags: [auth, security]
---

Use OAuth2 with PKCE for all client-side authentication flows.
```

**Addresses:** Failure 5 (schema drift).

### Principle 5: Know Your Retrieval Ceiling

**Why it works:** Every file-based retrieval mechanism has a ceiling beyond which it degrades. Understanding where your ceiling is prevents both premature optimization (adding vector search when grep suffices) and delayed migration (staying on files when queries have outgrown them).

The [Oracle/Richmond Alake benchmark](https://blogs.oracle.com/developers/comparing-file-systems-and-databases-for-effective-ai-agent-memory-management) quantifies this precisely: on large-corpus retrieval tasks, filesystem-based agents scored 29.7% while database-backed agents achieved 87.1% on identical queries. The gap exists because semantic retrieval surfaces conceptually relevant results even when vocabulary differs.

**How to apply:** Monitor your retrieval hit rate. Track how often the agent finds what it needs on the first query. When your hit rate drops below 80% using keyword search, you are approaching the ceiling. The migration triggers are:

1. **Queries require synonyms/paraphrases** ("login flow" should match "authentication process")
2. **Corpus exceeds ~5MB total** or ~1,000 discrete entries
3. **Multiple agents need concurrent semantic search** on shared memories
4. **You are building indexing, locking, recovery, and metadata logic around files** -- at this point, as [Oracle's analysis](https://blogs.oracle.com/developers/comparing-file-systems-and-databases-for-effective-ai-agent-memory-management) notes, "you're no longer 'just using files' -- you're rebuilding a database"

**Addresses:** Failure 4 (needle-in-haystack) by making the failure condition explicit and measurable.

---

## Evaluation: Real-World File-Based Memory Systems

| System | Level | Corpus Limit | Concurrency | Strength | Weakness |
|---|---|---|---|---|---|
| Claude Code MEMORY.md | 2 (Multi-file) | 200 lines hard cap | Single agent | Enforced size cap, 96% compliance on modular rules | No semantic search, 62% of issues from stale entries |
| Manus task_plan.md | 1 (Single file) | Unbounded | Single agent | Simple, effective for task continuity | No eviction, no concurrency, no query capability |
| OpenClaw | 3 (Folder + index) | ~5MB practical | Single agent | Hybrid search (89% recall), graceful degradation | Complex setup, SQLite dependency for search |
| STELE | 4 (SQLite + FTS5) | 10,000+ entries | Multi-agent (scoped) | 42ms p50 queries, four scope levels, built-in UI | 46 MCP tools is a large surface area |
| ShieldCortex | 2-3 (Files + scoring) | Bounded by decay | Single agent | Salience scoring with exponential decay solves eviction | Six-layer security pipeline adds latency |
| memv | 4 (SQLite) | Unbounded | Single agent | Stores only facts the agent failed to predict | No multi-agent support, single-instance design |

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2d3748', 'primaryTextColor': '#e2e8f0', 'primaryBorderColor': '#4a5568', 'lineColor': '#a0aec0', 'secondaryColor': '#4a5568', 'tertiaryColor': '#1a202c'}}}%%
quadrantChart
    title File-Based Memory Systems: Simplicity vs Capability
    x-axis Low Capability --> High Capability
    y-axis Complex --> Simple
    quadrant-1 "Sweet spot"
    quadrant-2 "Too simple"
    quadrant-3 "Overengineered"
    quadrant-4 "Capable but complex"
    "Claude Code MEMORY.md": [0.25, 0.90]
    "Manus task_plan.md": [0.15, 0.95]
    "OpenClaw": [0.65, 0.45]
    "STELE": [0.80, 0.25]
    "ShieldCortex": [0.55, 0.50]
    "memv": [0.70, 0.35]
    "Single progress.json": [0.20, 0.98]
```

---

## Recommendations

### Short-Term: Start with What Works (Week 1)

1. **Implement a progress.json checkpoint file** for every long-running agent. Read at session start, write after each significant step. Use atomic writes. This alone solves the most common memory complaint: "my agent forgot what it was doing." *(Implements Principle 2)*

2. **Cap your memory files at 200 lines**. If using MEMORY.md or equivalent, enforce the cap with automated rotation. Archive overflow to dated files. *(Implements Principle 1)*

3. **Add JSON Schema validation** to every state file write. Catch schema drift at write time, not read time. *(Implements Principle 4)*

### Medium-Term: Add Structure (Weeks 2-4)

4. **Split monolithic memory into typed files** with a maintained index. Separate decisions, preferences, patterns, and session state. Keep each file under 2,000 tokens. Maintain MEMORY.md as the discovery index. *(Implements Principle 3)*

5. **For multi-agent systems, start with orchestrator-mediated writes** using atomic file operations. Only escalate to file locking or SQLite when write frequency exceeds ~1/minute per shared file. *(Implements Principles 2 and 3)*

6. **Instrument retrieval hit rate.** Track how often the agent finds the right memory on the first query. This is your early warning system for when files are no longer sufficient. *(Implements Principle 5)*

### Long-Term: Graduate When You Must (Month 2+)

7. **Migrate to SQLite + FTS5 when** corpus exceeds ~1,000 entries, queries require stemming/phrase matching, or multi-agent writes exceed what orchestrator serialization can handle. SQLite is still a single file -- the operational overhead increase is minimal. *(Implements Principle 5)*

8. **Add vector search only when** queries require semantic similarity (synonym/paraphrase matching) AND keyword retrieval hit rate drops below 80%. The hybrid approach (70% vector + 30% BM25 weighting, as OpenClaw implements) achieves [89% recall](https://dev.to/imaginex/ai-agent-memory-management-when-markdown-files-are-all-you-need-5ekk) -- significantly better than either approach alone.

9. **Do not skip levels.** Going directly from a progress.json to a vector database is overengineering. Each level in the spectrum exists because the previous level's failure mode forced the upgrade. If you have not hit the failure mode, you do not need the upgrade.

---

## The Hard Truth

Most teams debating "which vector database should we use for agent memory" have not yet tried a JSON file. This is not an exaggeration. The [existing analysis in this series](memory-and-state-management.md) states it directly: "Most teams building agentic systems do not have a memory problem. They have a session continuity problem -- and the solution is a progress file, not a vector database."

The uncomfortable reality is that file-based memory is boring, and boring solutions do not generate conference talks, blog posts, or venture funding. But Claude Code -- one of the most capable AI coding agents in production -- runs its entire memory system on markdown files with a 200-line hard cap. Manus, acquired for $2B, uses `task_plan.md`. These are not MVPs waiting to be upgraded. They are deliberate architectural choices by teams that understand where complexity belongs.

Where people go wrong is in two symmetric ways. Premature optimization: reaching for Pinecone when a JSON file would suffice, adding 30ms of retrieval latency and $200/month for a problem that does not exist yet. And delayed migration: keeping files past their expiration date, implementing locking, indexing, recovery, and metadata management around flat files until the system is -- as the Oracle analysis puts it -- "no longer 'just using files' but rebuilding a database, poorly."

The line between these two errors is not fuzzy. It is a phase transition at roughly 1,000 discrete memories and the first query that requires understanding meaning rather than matching keywords. Below that line, files win on every axis: cost ($0.02/GB/month vs. $50-200/GB/month for managed vector DBs), latency (disk read vs. embedding + search), debuggability (cat the file vs. inspect vector space), and operational overhead (zero vs. a service to maintain). Above that line, files lose on the only axis that matters: retrieval quality (29.7% vs. 87.1%).

The one thing to remember: **start with the simplest thing that could work, instrument it so you know when it stops working, and upgrade only when the data tells you to.**

---

## Summary Checklist

| Question | Good Answer | Bad Answer |
|---|---|---|
| Do you have a progress checkpoint file for long-running agents? | Yes, read at session start, written after each step | No, agent starts fresh each session |
| Are your file writes atomic? | Yes, write-to-temp-then-rename pattern | No, direct write to target file |
| Do your memory files have a size cap? | Yes, enforced mechanically with automated rotation | No, or "we try to keep them small" |
| How do you find relevant memories? | Index file + scoped search, monitored hit rate | Load all files into context every time |
| How do multiple agents coordinate writes? | Orchestrator-mediated or SQLite serialization | Each agent writes independently (last-write-wins) |
| Do you validate schema on write? | Yes, JSON Schema or structured frontmatter validation | No, "it's just a JSON file" |
| When would you switch to a vector database? | When keyword retrieval hit rate drops below 80% and queries require semantic similarity | "We need one from the start" or "Never, files are fine" |
| Is your memory observable? | Yes, retrieval hit rate tracked, file sizes monitored | No, "it works until it doesn't" |
| Does your system handle partial writes / crashes? | Yes, atomic writes + schema validation on read | No, assumes writes always complete successfully |
| Can you explain why your current storage level is correct? | Yes, based on corpus size, query type, and concurrency requirements | "It's what we've always used" or "It's what the tutorial showed" |

---

## References

### Practitioner Articles

- [AI Agent Memory Management: When Markdown Files Are All You Need](https://dev.to/imaginex/ai-agent-memory-management-when-markdown-files-are-all-you-need-5ekk) -- Comparison of Manus, OpenClaw, and Claude Code memory architectures; 89% hybrid recall benchmark; scalability thresholds for file-based approaches.
- [The MEMORY.md Problem: Why Local Files Fail at Scale](https://dev.to/anajuliabit/the-memorymd-problem-why-local-files-fail-at-scale-58ae) -- Documented failure case of a MEMORY.md growing to 15,000 tokens with 47 contradictory preferences; $555/month cost analysis.
- [Claude Code Memory System Deep-Dive](https://institute.sfeir.com/en/claude-code/claude-code-memory-system-claude-md/deep-dive/) -- Compliance rate benchmarks (92% under 200 lines, 71% over 400 lines); 62% staleness problem; token consumption analysis.
- [Claude Code Memory Architecture](https://ianlpaterson.com/blog/claude-code-memory-architecture/) -- Practitioner case study running 34 projects on plain markdown + SyncThing with cron-based rotation and 8 design rules.
- [Writing a Good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md) -- Anti-patterns (auto-generating with /init, stuffing style guidelines, context bloat); production CLAUDE.md under 60 lines.
- [Building Local Memory for Coding Agents](https://muhammadraza.me/2026/building-local-memory-for-coding-agents) -- FTS5 + sqlite-vec hybrid implementation; cross-agent vault; "for most use cases, FTS5 is all you need."
- [Context Engineering for Coding Agents](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) -- Context engineering taxonomy; minimal viable context principle; "an agent's effectiveness goes down when it gets too much context."

### Research and Analysis

- [Why Multi-Agent Systems Need Memory Engineering](https://www.oreilly.com/radar/why-multi-agent-systems-need-memory-engineering/) -- 36.9% failure rate from interagent misalignment; 15x token multiplication; five pillars of multi-agent memory; "silent last-write-wins is almost never correct."
- [Comparing File Systems and Databases for AI Agent Memory](https://blogs.oracle.com/developers/comparing-file-systems-and-databases-for-effective-ai-agent-memory-management) -- FSAgent 29.7% vs MemAgent 87.1% benchmark; concurrency integrity tests; "the reinvention trap" argument.
- [AGENTS.md Context File Value Review](https://www.infoq.com/news/2026/03/agents-context-file-value-review/) -- ETH Zurich research: LLM-generated context files reduced success by 3% and increased costs by 20%; human-written files improved success by only 4%.
- [Memory in AI Agents](https://www.leoniemonigatti.com/blog/memory-in-ai-agents.html) -- CoALA and Letta memory taxonomy frameworks; four memory types with storage pattern guidance.
- [Files Are All You Need](https://www.llamaindex.ai/blog/files-are-all-you-need) -- File search outperforms naive semantic search on small-to-medium collections; crossover point analysis.

### Official Documentation

- [Claude Code Memory](https://code.claude.com/docs/en/memory) -- Official documentation for CLAUDE.md, MEMORY.md, modular rules, and auto-memory.
- [AGENTS.md Specification](https://agents.md/) -- Flexible markdown format for AI coding assistant context; 60,000+ repo adoption; Linux Foundation governance.
- [Cursor Rules](https://cursor.com/docs/context/rules) -- Four rule types (Always On, Auto Attached, Model Decision, Manual); MDC format; glob pattern matching.
- [sqlite-memory](https://github.com/sqliteai/sqlite-memory) -- SQLite extension for markdown-aware semantic search; FTS5+vector hybrid; atomic SAVEPOINT transactions.
- [OpenClaw Local-First RAG](https://www.pingcap.com/blog/local-first-rag-using-sqlite-ai-agent-memory-openclaw/) -- Four-table SQLite schema; graceful degradation pattern; zero-ops deployment.

### Tools and Implementations

- [STELE](https://www.reddit.com/r/LLMDevs/comments/1r8zq5c/looking_for_early_testerscollaborators_stele_a/) -- Local-first memory with SQLite backend; four scope levels; 42ms p50 query latency; 46 MCP tools.
- [memv](https://www.reddit.com/r/LLMDevs/comments/1r1zomd/memv_opensource_memory_for_ai_agents_that_only/) -- Predict-calibrate extraction; stores only facts the agent failed to predict; SQLite backend.
- [ShieldCortex](https://www.reddit.com/r/LocalLLaMA/comments/1r5eeht/ai_agents_forget_everything_between_sessions_i/) -- Local-first persistent memory for coding agents; salience scoring with exponential decay.
- [AI Coding Config Files Guide](https://www.deployhq.com/blog/ai-coding-config-files-guide) -- Cross-tool comparison of all AI coding config file formats with capacity constraints.
