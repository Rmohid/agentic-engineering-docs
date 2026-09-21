# Changelog

All notable changes to this guide are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [September 2026] — second edition

Every document was reviewed against what changed since March 2026. Three
documents were added for subjects that did not have one.

### Added

- **21. [Agent Skills and Procedural Memory](docs/agent-skills-and-procedural-memory.md)** —
  why an agent relearns a procedure every session unless the procedure is
  written down as a selectable artifact, and why selection, not authoring, is
  the scarce resource in a skill library.
- **22. [Unattended Agent Operations](docs/unattended-agent-operations.md)** —
  what changes when an agent runs on a schedule with nobody at the keyboard:
  permissions per actor class, a durable ledger instead of a live coordinator,
  and a spending brake that reads a counter which only moves one way.
- **23. [Agent Governance and Intent Records](docs/agent-governance-and-intent-records.md)** —
  the layer above the rules: a tree of outcomes in which every rule hangs off
  the outcome it serves, every mechanically checkable rule carries a gate, and
  every unenforceable standard is recorded as a gap rather than asserted.
- **A currency footer on every document.** Each one now ends with the date it
  was last reviewed and a one-line list of what changed.
- **A "Field Notes from an Operating Estate" section on every document.** One
  to three short first-person observations, dated by month, from operating
  agents against these APIs daily. Each is abstracted to the pattern; no
  internal system, path, or person is named.
- This changelog.

### Changed

- **Model lineup, pricing, and context windows replaced throughout.** Current
  model names, per-token prices, context-window sizes, and long-context
  surcharges now appear in place of the March values.
- **Structured output.** Every major provider now compiles a schema into a
  grammar and masks invalid tokens during generation. The remaining failures
  are semantic rather than syntactic, so validation of meaning is still the
  caller's job. The document was rewritten around that.
- **Retrieval.** The ceiling on a retrieval-augmented system is set at chunking
  time, before any vector database is compared — not by the embedding model.
- **The framework landscape was recounted.** The companion reference mapped 22+
  third-party frameworks across seven layers in March 2026; it now maps 31
  current products across the same seven layers, and carries a churn table of
  the 2026 acquisitions, mergers, and shutdowns.
- **Prompt injection.** The evidence now points at containment rather than at
  model quality: the same model has been measured at a 0% and a 78.6% injection
  success rate across two environments, with only its permitted actions
  differing.
- **Fine-tuning.** The durable place to run it, as of this revision, is an
  open-weight model.
- **[docs/index.md](docs/index.md)** documents 23 deep-dives, adds a Tier 6
  section, and carries a "What Changed in the September 2026 Revision" section.

### Fixed

- The document count was wrong in two places. The read-me file claimed 17
  documents and the index claimed 20, against 23 files on disk. Both now state
  23.
- The index stamped its consensus as "as of March 2026". It now reads September
  2026.

---

## [July 2026]

### Added

- **[File-Based Memory for AI Systems](docs/file-based-memory-for-ai-systems.md)** —
  a companion reference on persistent memory for AI coding agents using the
  file system, without external infrastructure.

---

## [March 2026] — first edition

### Added

- 20 deep-dive documents across five tiers, from LLM fundamentals to
  self-improving systems.
- **[docs/index.md](docs/index.md)** — a five-tier reading path, per-document
  summaries, and a problem-pattern lookup table.
- **The AI-Native Framework Landscape** — a companion reference mapping 22+
  third-party frameworks across seven layers of the stack.
- **`.claude/commands/deep-dive.md`** — the generation command used to produce
  the suite, so anyone who clones the repository can regenerate it.
