Produce a publication-quality deep-dive document on a topic, with Mermaid diagrams, failure taxonomies, concrete examples, and actionable recommendations.

## Input

$ARGUMENTS

The input is a topic or question. Examples:
- `/deep-dive consensus algorithms`
- `/deep-dive why microservices fail`
- `/deep-dive CQRS vs event sourcing tradeoffs`
- `/deep-dive how container networking actually works`

If $ARGUMENTS is empty, ask the user what topic they want explored.

## Instructions

You are producing a deep-dive document -- not a summary, not a tutorial, not a blog post. A deep-dive goes beyond surface-level explanations to uncover **why things work the way they do**, **how they fail**, and **what to actually do about it**. The reader should finish feeling like they genuinely understand the topic, not like they read a Wikipedia page.

### Phase 1: Scope and Research

#### Step 1: Scope the topic

Parse $ARGUMENTS. Determine whether the topic is focused enough for a single document.

- **Focused** (e.g., "quality gates in agentic systems", "why RAFT consensus is hard to implement"): Proceed to Step 2.
- **Too broad** (e.g., "machine learning", "distributed systems"): Ask the user ONE clarifying question to narrow scope. Propose 2-3 focused angles and ask which they want. Do not proceed until scope is clear.
- **Too narrow** (e.g., "the third parameter of fmt.Sprintf"): Widen slightly to make a meaningful document. Tell the user what scope you're using.

#### Step 2: Scan existing documents

Before researching, check the output directory for existing content to avoid duplication.

1. Determine the output directory (see Step 7 for the resolution order: explicit path in $ARGUMENTS, then `docs/` in cwd, then create `docs/`).
2. Glob the output directory for all `.md` files.
3. For each existing document, read the title (first `# heading`) and the first paragraph to build a topic inventory.
4. Compare the proposed deep-dive topic against the inventory.

**Three outcomes:**
- **No overlap**: Proceed to Step 3.
- **Partial overlap**: Identify which existing document covers what. Scope the new document to cover only the gap. Add cross-references to the existing document rather than duplicating its content. Tell the user what you're scoping out and why.
- **Full overlap**: Tell the user a document on this topic already exists at `<path>`. Offer to either (a) update/expand the existing document, or (b) proceed with a fresh take from a different angle. Do not proceed until the user decides.

#### Step 3: Parallel research

Launch **up to 3 parallel research agents** in a SINGLE message. Use only the agents that apply:

**Agent 1 -- Knowledge base search** (if a knowledge base or note system is available in the environment): Search for existing notes on the topic. Read the top results. Extract any prior knowledge, frameworks, or references. If no knowledge base is available, skip this agent and allocate its research scope to the web research agent.

**Agent 2 -- Web research**: Use WebSearch for 3-5 authoritative sources. Use WebFetch (prepend `https://r.jina.ai/` for cleaner output if available) to read the top results. Prefer practitioner blogs, conference talks, and technical deep-dives over vendor marketing. Follow the trusted source hierarchy:
- **Tier 1**: Simon Willison, Julia Evans, Martin Fowler
- **Tier 2**: Gergely Orosz, Armin Ronacher, Mitchell Hashimoto
- **Tier 3**: Swyx/Latent Space, Will Larson, Charity Majors, Dan Luu
- **Publications**: InfoQ, The New Stack, Lobsters, GitHub Blog
- **Communities**: Reddit practitioner discussions, HN deep threads

**Agent 3 -- Codebase context** (only if the topic relates to the current project): Search the local codebase with Glob and Grep for relevant implementations, patterns, or configurations that connect to the topic. Skip this agent if the topic is purely conceptual.

Synthesize all research findings before proceeding. **Critical: each research agent must return the exact URLs it fetched, along with a one-line summary of what each source contributed.** These URLs form the basis of the References section. Do not invent or guess URLs -- only include URLs that were actually fetched and read during research. If a web search returns a result that you did not fetch the full content of, do not include it as a reference.

### Phase 2: Structure

#### Step 4: Build the document skeleton

Every deep-dive follows this proven structure. The section names change per topic, but the *progression* is fixed:

```
1. THE PROBLEM / TENSION           (Why this topic matters)
   - Frame as a contradiction, tension, or non-obvious insight
   - Comparative table placing the topic in broader context
   - Mermaid diagram showing the core tension

2. FAILURE TAXONOMY                (How things go wrong)
   - 3-7 distinct failure modes, each with:
     - What it looks like
     - Why it happens (root cause, not surface symptom)
     - Concrete example (code, scenario, or real incident)
   - Diagnosis before prescription -- never propose solutions here

3. SPECTRUM / PROGRESSION          (A framework for reasoning)
   - Levels, stages, maturity model, or tradeoff spectrum
   - Each level with concrete characteristics and examples
   - Mermaid diagram showing the progression
   - This section gives the reader a mental model to evaluate their own situation

4. PRINCIPLES / SOLUTIONS          (What to actually do)
   - 4-7 principles, each with:
     - The principle stated clearly
     - WHY it works (connect back to failure modes it addresses)
     - HOW TO APPLY (concrete, actionable steps)
     - Mermaid diagram or code block showing the pattern
   - Each principle should directly counter 1+ failure modes from section 2

5. EVALUATION                      (Grading real systems)
   - If the topic relates to a specific system, codebase, or tool: grade it
   - Table with columns: Component | Level/Score | Strength | Weakness
   - Mermaid quadrant chart if comparing multiple items
   - Skip this section if the topic is purely theoretical

6. RECOMMENDATIONS                 (Prioritized action plan)
   - Short-term (easy wins, immediate improvements)
   - Medium-term (structural changes)
   - Long-term (architectural shifts)
   - Each recommendation references the principle it implements

7. THE HARD TRUTH                  (The uncomfortable summary)
   - 1-2 paragraphs stating the core insight bluntly
   - What most people get wrong about this topic
   - The one thing the reader should remember

8. SUMMARY CHECKLIST               (Decision matrix)
   - 6-10 binary questions with Good Answer / Bad Answer columns
   - Reader can evaluate their own situation mechanically

9. REFERENCES                       (Verifiable sources)
   - Every source consulted during research, with clickable URLs
   - Grouped by type: research papers, practitioner articles, official docs, tools
   - Each reference includes a one-line annotation of what it contributed
   - If a claim in the document draws heavily from a specific source, cite it inline as [Source Name](URL)
```

Not every section will be the same length. Scale each section to its complexity: a few sentences if straightforward, up to 500 words if the topic demands it. The failure taxonomy and principles sections will usually be the longest.

**If a section doesn't apply to the topic** (e.g., "Evaluation" for a purely theoretical topic), skip it. Do not force sections that add no value. But you need a strong reason to skip -- the default is to include all sections.

### Phase 3: Write

#### Step 5: Write the document

Follow these rules strictly:

**Content rules:**
- **Problem-first, solutions-second.** Never prescribe without diagnosing. The reader must understand why something fails before they'll trust your advice on how to fix it.
- **"Why" before "what" at every level.** Don't just state that X is true. Explain the mechanism that makes it true.
- **Concrete examples for every claim.** No principle without a code block, scenario, or real-world case. Abstract advice is worthless. "Use caching" is worthless. "Use a read-through cache at the API gateway because DB round-trips add 40ms per request and your p99 is already at 800ms" is actionable.
- **Progressive revelation.** Early sections are conceptual (40% of document). Middle sections add structure and measurement (40%). Final sections are operational recommendations (20%). Do not front-load actionable advice -- earn the reader's trust with diagnosis first.
- **Cite your sources inline.** When stating a statistic, research finding, benchmark result, or specific technical claim from an external source, link to it inline: e.g., "models rate their own outputs 10-25% higher ([LLM Self-Preference Study](https://example.com/study))". The reader must be able to verify any non-obvious factual claim. Claims that are common knowledge or the author's own analysis do not need citations.

**Visual rules:**
- Use Mermaid diagrams at structural transitions where spatial reasoning aids understanding. A simple topic may need 1-2; a complex topic may need 6+. The number should match the topic's complexity, not a quota.
- Use tables when comparing 3+ items across multiple dimensions. If the topic doesn't involve comparisons or taxonomies, fewer tables is fine.
- Use Mermaid `theme: "base"` with explicit `themeVariables`. Group nodes by shade into subgraphs. Set `edgeLabelBackground` to match `clusterBkg`. Never mix light and dark fills in the same subgraph.
- Appropriate diagram types by purpose:
  - **graph TD/LR**: Decision flows, failure paths, data flow
  - **sequenceDiagram**: Multi-actor interactions, protocol flows
  - **quadrantChart**: Comparing items on two axes
  - **pie**: Distribution breakdowns
  - **stateDiagram-v2**: State machines, lifecycle transitions
- Do NOT use diagrams as decoration. Every diagram must convey information that is harder to express in text.

**Formatting rules:**
- Title: `# <Topic>: <Insight or Framing>` (e.g., "Quality Gates in Agentic Systems: Why They Fail and How to Make Them Reliable")
- Subtitle: One sentence framing the document's angle
- Horizontal rules (`---`) between major sections
- Bold for key terms on first use
- Code blocks for examples, commands, and configurations
- No emojis anywhere

**Length target:** 2,000-5,000 words depending on topic complexity. Shorter is better if depth is maintained. Do not pad.

#### Step 6: Self-review before saving

Before writing the file, verify against this checklist:

- [ ] Opens with a tension/contradiction, not a definition
- [ ] Has a comparative table in the first section
- [ ] Diagnoses failures BEFORE proposing solutions
- [ ] Every principle has a "why it works" and "how to apply"
- [ ] Diagrams are used where they aid comprehension, not as decoration
- [ ] Tables are used for comparisons and taxonomies where appropriate
- [ ] Concrete examples (code, scenarios, incidents) for every major claim
- [ ] Ends with an actionable checklist or decision matrix
- [ ] No section is pure abstract advice without grounding
- [ ] "The Hard Truth" section says something non-obvious
- [ ] No content duplicates an existing document in the output directory
- [ ] References section lists every source with clickable URLs
- [ ] Every major factual claim, statistic, or research finding has an inline citation linking to its source
- [ ] No reference is fabricated -- every URL was actually fetched during research

If any item fails, revise before saving.

### Phase 4: Deliver

#### Step 7: Save the document

Determine save location:
1. If $ARGUMENTS contains a path (e.g., `/deep-dive ~/docs/caching.md consensus algorithms`), use that path
2. If the current working directory has a `docs/` folder, save to `docs/<topic-slug>.md`
3. Otherwise, create `docs/` in the current working directory and save there

The topic slug should be lowercase, hyphenated, descriptive (e.g., `quality-gates-in-agentic-systems.md`, `why-microservices-fail.md`).

#### Step 8: Open the file

Open the saved document for the user. On macOS: `open <file-path>`.

## Quality Standard

Every document produced by this command should meet these bars:
- Depth of "why" explanations -- mechanisms, not surface descriptions
- Density of concrete examples -- code, scenarios, or real incidents for every major claim
- Structural progression from problem to solution -- diagnosis before prescription, always
- Visual information density -- diagrams and tables where they aid comprehension
- Actionability of the final recommendations -- specific enough to act on without further research

If you would not be proud to show the document to someone deeply knowledgeable in the topic, it is not done.

## Rules

1. **Never write a summary.** Summaries skim surfaces. Deep-dives dig foundations. If a section reads like it could appear in a "What is X?" blog post, rewrite it.
2. **Never define without demonstrating.** Definitions go in dictionaries. Examples go in deep-dives. Show, don't tell.
3. **Never recommend without diagnosing.** The failure taxonomy must come before the principles section. Always.
4. **Never use a diagram as decoration.** Every diagram must convey information that is harder to express in prose. A flowchart that restates what the text already says is clutter.
5. **Be honest about uncertainty.** If the research is thin on a sub-topic, say so. "This area is underexplored" is more useful than confident-sounding speculation.
6. **Scale to the topic.** A deep-dive on a simple topic (e.g., "how DNS resolution works") might be 2,000 words. A deep-dive on a complex topic (e.g., "distributed consensus tradeoffs") might be 5,000. Don't pad and don't truncate.
7. **The Hard Truth section must be uncomfortable.** If it reads like a pleasant conclusion, you have not been honest enough. State the thing most people in the field get wrong or don't want to hear.
8. **Never duplicate existing content.** If the output directory already has a document covering the topic, either scope around it or update it -- never write overlapping content.
9. **Every factual claim must be traceable.** When citing a statistic, research finding, or specific technical detail from an external source, include an inline link: `[Source Name](URL)`. The reader must be able to verify any non-obvious claim by clicking through to the original source. Do not cite URLs you did not actually fetch during research.
10. **The References section is mandatory.** Every deep-dive must end with a References section listing all sources consulted, with clickable URLs and one-line annotations. Group by type: research papers, practitioner articles, official documentation, tools/frameworks. If a source was fetched but contributed nothing useful, omit it. If a claim has no source, either find one or explicitly mark it as the author's analysis.

## Allowed Tools

allowed-tools: Agent, Read, Write, Edit, Glob, Grep, Bash, WebSearch, WebFetch, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot
