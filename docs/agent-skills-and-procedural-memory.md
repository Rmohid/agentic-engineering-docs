# Agent Skills and Procedural Memory: An Agent That Only Follows Its System Prompt Relearns Nothing

**Thesis:** An agent does not learn a procedure by being told it once. It relearns it every session unless the procedure is written down as a *selectable* artifact — a skill: a named, loadable procedure with a trigger, an order, its pitfalls, and a check. Writing skills is the easy half. Selection is the scarce resource: a library grows more valuable and less usable at the same rate, and a skill that is never selected is dead weight the context budget still pays for.

**Prerequisites:** [Context Engineering](context-engineering.md) (context budgets, information placement), [Prompt Engineering](prompt-engineering.md) (system prompts, instruction structure), [Memory and State Management](memory-and-state-management.md) (the memory taxonomy this document extends with a third kind), and [Tool Design for LLM Agents](tool-design-for-llm-agents.md) (why tool definitions consume context permanently).

**Reading time:** 18 minutes

| What teams assume | What actually happens |
|---|---|
| "A skill is a long prompt you saved to a file." | A skill's first job is to be *found*, not read. Only `name` and `description` are required, and they are the only two fields the agent sees at selection time ([Agent Skills specification](https://agentskills.io/specification)). |
| "Bigger instruction files mean better compliance." | In the only controlled factorial study of the question, file size from 25 to 500 lines produced **no detectable effect** on instruction compliance across 1,650 sessions (the size null carries an affirmative-null Bayes factor of 0.05–0.10). The largest effect measured was *within* a session: each additional function the agent generated lowered the odds of compliance by roughly 5.6% ([McMillan, 2026](https://arxiv.org/abs/2605.10039)). |
| "Write the skill and the agent will use it." | Force-loading curated skills scored 55.4%; letting the agent choose from the same set dropped to 51.2%; distractors dropped it to 43.5%. Only 49% of trajectories loaded all available curated skills, falling to 31% with distractors and 16% with none in the pool ([Skill-Usage, 2026](https://arxiv.org/abs/2604.04323)). |
| "Let the agent write its own skills — it knows what worked." | Self-generated skills averaged **−1.3 percentage points** against a no-skill baseline; human-curated skills averaged **+16.2** ([SkillsBench, 2026](https://arxiv.org/abs/2602.12670)). |
| "A skill library only grows. More coverage is more capability." | Unbounded accumulation without retirement is a named failure mode — *library drift* — degrading retrieval and stagnating performance. The mirror error is measured too: premature retirement *harmed* performance ([Library Drift, 2026](https://arxiv.org/abs/2605.19576)). |
| "Once a skill is correct, it stays correct." | Skills decay as the services, packages, and APIs they reference move. Drift is role-dependent — a version string in a comment is noise, the same string in a pinned dependency is an obligation — and contract-free monitoring produced 40% false positives ([Skill Drift, 2026](https://arxiv.org/abs/2605.10990)). |
| "Skills, tools, and subagents are variations on the same thing." | Three context devices: tools carry *connectivity* and cost context permanently; skills carry *procedure* and cost nothing until matched; subagents carry *isolation* and return only a summary ([Skills explained, 2026](https://claude.com/blog/skills-explained)). |

## The Core Tension

Every token an agent holds is paid on every task; every skill it holds, only when matched.

Put a procedure in the always-loaded instruction file and it competes with the task forever. Put it in a skill and it costs roughly a hundred tokens until it is needed. That is a spectacular trade until you ask: *what makes the agent reach for it?*

Nothing, unless the description matched the situation. An agent cannot discover a skill it was not told about, and it is only told the `name` and `description`. The body — the steps, the pitfalls, the verification — is invisible at selection time. So the artifact that carries the procedure is not the artifact that gets it used: the trigger is.

Skill utility is *fragile*, not additive: force-loaded curated skills 55.4%, agent-selected from the same set 51.2%, with distractors 43.5%, retrieved from a large pool 40.1%, and 38.4% when the pool held only general-purpose skills — 3.0 points above the no-skill baseline, with skill usage down to 16% of trajectories. Two models finished *below* their own no-skill baselines: irrelevant retrieved procedures did not merely fail to help, they actively misled ([Skill-Usage, 2026](https://arxiv.org/abs/2604.04323)).

The question is not how to write a skill; the specification answers that. It is how a library stays useful as it grows.

## Procedural Memory, and Why It Is Harder Than Facts

Memory is at least two things, not one.

**Declarative memory** holds facts — a customer's plan tier, a repository's module layout, the service that owns billing. Facts are retrieved by *topic similarity*: embed the question, embed the fact, take the nearest neighbour. They are idempotent, unordered, and mergeable, so a summarizer can compress a hundred facts into ten without destroying any.

**Procedural memory** holds *how to do something* — how this organization rotates a signing key, how a release is cut, how a flaky integration test is quarantined. Procedures differ from facts in four ways, and each is a failure mode in disguise.

1. **A procedure has a trigger, not a topic.** "Use when the deploy pipeline reports a stale lock" is a trigger. "Deployment notes" is a topic, and it will not fire.
2. **A procedure has order.** Step 4 before step 3 is a bug, not a style choice. A compressor that summarizes a procedure destroys it, because the compression is lossy exactly where the meaning lives — hence the specification's hard budget on the body.
3. **A procedure has a validity window.** A fact is stale when the world changes observably; a procedure is stale when an assumption inside it silently stops holding. It was correct when written, is wrong now, and nothing raises an error (Failure 2).
4. **A procedure cannot be reliably self-authored.** The shortcut — let the agent write down what worked — is measured, and it does not work: self-generated skills returned −1.3 percentage points against a no-skill baseline while curated ones returned +16.2. The trajectory analysis names the two failure shapes: models identify *that* domain knowledge is needed but generate imprecise procedures ("use pandas for data processing", with no API pattern), and on high-domain-knowledge tasks they fail to recognise the need for a specialized procedure at all ([SkillsBench, 2026](https://arxiv.org/abs/2602.12670)).

Point four is the one practitioners resist: an agent that just solved a problem appears to know how it solved it. It does not know how to write the procedure that would let a *fresh* session solve it — one with no memory of the dead ends, or of the approaches that looked right and were not. Human curation is the only measured source of working procedural knowledge.

## The Skill as a Context Device

Skills are one of five ways to put something in an agent's context.

| Device | What it carries | When it enters context | Idle cost |
|---|---|---|---|
| Instruction file (`AGENTS.md`, `CLAUDE.md`) | Standing policy, conventions, constraints | Always, from session start | Full file, every turn |
| Tool definitions (MCP, function schemas) | Connectivity — what the agent can *do* | Always, as a schema | Full schema, every turn |
| **Skill** | **A procedure — how to do it well** | Metadata always; body on match; resources on demand | ~100 tokens per skill |
| Subagent | Isolation — a task in a clean context window | On delegation | Zero; a summary returns |
| Retrieval (RAG) | Facts and documents | On query | Zero |

**Progressive disclosure is the mechanism, not a nicety.** The specification defines three tiers: `name` and `description` load at startup for every skill at roughly 100 tokens each; the full body loads on activation, recommended under 5,000 tokens; and bundled files in `scripts/`, `references/`, or `assets/` load only when the instructions call for them. The main file should stay under 500 lines ([Agent Skills specification](https://agentskills.io/specification); [Claude platform docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).

**The agent cannot discover what it was not told about.** There is no scan of the library at selection time; selection sees the metadata tier and nothing else. That is why routing degrades sharply at scale: on a benchmark of roughly 80,000 skills, hiding the skill *body* and exposing only names and descriptions cost 31 to 44 points of routing accuracy. The body is the decisive signal in a large, overlapping pool ([SkillRouter, 2026](https://arxiv.org/abs/2603.22455)).

**Tools, skills, and subagents are complementary, not competing.** A tool is a capability the agent invokes; a skill is a procedure it follows; a subagent is a context window it delegates into — a schema, a procedure, or a boundary ([Skills explained](https://claude.com/blog/skills-explained); [subagents](https://docs.claude.com/en/docs/claude-code/sub-agents)).

## The Anatomy of a Skill

A skill that works has six parts: five of content, one that makes it retirable.

**1. The trigger.** The `description` states what the skill does *and when to use it*, in the words the task will arrive in. The specification's own contrast is instructive: "Use when working with PDF documents or when the user mentions PDFs, forms, or document extraction" — good; "Helps with PDFs" — poor, and it fails silently forever, because nothing about it will match a task ([Agent Skills specification](https://agentskills.io/specification)).

**2. The ordered procedure.** Numbered steps with explicit inputs and outputs. Order is information: if two steps are genuinely interchangeable, say so.

**3. The pitfalls.** The failures the author paid for. This section most distinguishes a curated skill from a generated one, and it is the one a self-authored skill reliably omits — the model that hit the dead end has no memory of having hit it.

**4. The verification step.** A check the skill can actually run, whose output decides whether the procedure worked. Without it, "the skill worked" is the agent's own assessment — the weakest evidence in the system. The instruction should be "run this and report the result", never "confirm that this succeeded".

**5. The exit condition.** The point at which the agent should stop following the skill and re-derive. Every procedure has a boundary past which its assumptions no longer hold; a skill that does not name it invites Failure 5.

**6. The retirement condition.** The problem the skill solves, and the thing whose disappearance would make it pointless. A skill that names its own obsolescence can be retired by evidence rather than archaeology — "retire this when the pipeline reports structured errors directly" is checkable; "is this still needed?" is a meeting.

The published best-practice list from a shipping implementation converges on the same shape: keep each skill focused on one job; prefer instructions over scripts unless you need deterministic behaviour; write imperative steps with explicit inputs and outputs; and test prompts against the description to confirm the trigger fires ([Codex skills documentation](https://developers.openai.com/codex/skills)). That last item is the one teams skip — a unit test for the only part read at selection time.

## Failure Taxonomy

### Failure 1: The Skill That Is Never Selected

The skill is correct, well written, and never loaded. There is no error, no warning, and no metric — the library grows while its effect stays flat. **Diagnosis:** selection is failing, not the procedure.

### Failure 2: The Stale Skill

The procedure was correct when written and is wrong now, because something it references moved. The failure is silent by construction: end-task metrics drift down with no error signal. Monitoring raw environmental change is not the answer: contract-free CI-style probes produced 40% false positives. The distinction that works is role — the same version string is noise in a comment and an obligation in a pinned dependency. Validating only role-bearing assumptions raised zero false alarms across 599 no-drift and hard-negative cases, with 86% conservative precision over 49 real skills, and localization made repair actionable: one-round success rose from 10% to 78% ([Skill Drift, 2026](https://arxiv.org/abs/2605.10990)).

### Failure 3: The Contradicting Pair

Two skills disagree, and the agent that loads both follows whichever it read last. The measured version is the negative delta: 16 of 84 benchmark tasks performed *worse* with curated skills than without, one by 39.3 points, which the paper reads as skills introducing "conflicting guidance or unnecessary complexity for tasks models already handle well" ([SkillsBench, 2026](https://arxiv.org/abs/2602.12670)). The same smell appears in configuration files as *Conflicting Instructions*, co-occurring with context bloat to raise its likelihood by 83% ([Configuration Smells, 2026](https://arxiv.org/abs/2606.15828)). **Fix:** one owner per procedure.

### Failure 4: The Workaround That Outlived Its Bug

A skill encodes a workaround for a defect that was later fixed. The workaround now costs work on every run and protects against nothing. It is the most common stale-skill variant in fast-moving codebases: the bug was closed in another repository by another person, and the procedure that routes around it carries no pointer to it. **Fix:** the skill cites the defect it works around, in a form a search can find, so closing the defect makes the skill greppable. A workaround without a citation is permanent by accident.

### Failure 5: Letter Over Intent

The agent follows the procedure past the point where it stopped being right: the step says restart the service, so it restarts the service, on the host where the service is the thing holding the lock. This is over-obedience rather than disobedience, and it is what makes people distrust skills altogether. The counter is structural: name the exit condition, and make the verification step capable of *failing*. A check that can only pass is an instruction to proceed.

### Failure 6: Skill Leakage

Procedural content parked in the always-loaded instruction file instead of a loadable skill. Measured at ecosystem scale: among 100 popular repositories carrying an agent configuration file, *Skill Leakage* appeared in 35%, *Context Bloat* in 42%, and 91 of the 100 carried at least one of six catalogued smells. One file in that study was reorganised across 27 sections, and its own pull request argued for shrinking it from 598 lines to 149 because the guidance "would be better maintained in separate documentation or loaded on demand through skills" ([Configuration Smells, 2026](https://arxiv.org/abs/2606.15828)). **Fix:** the test is "is this needed on *every* task?"

### Failure 7: Library Drift

Unbounded accumulation without outcome-driven lifecycle management: the library degrades retrieval precision, injects stale or harmful guidance, and effective performance stagnates or falls below the no-skill baseline. The diagnosis is uncomfortable because the symptom is aggregate: scores decline gradually with no explicit error. The measured fix is a minimal governance recipe (outcome-driven retirement, a bounded active cap, an authoring prior) which lifted held-out pass@1 from a 0.258 baseline to a late-window mean of 0.584 over 100 rounds. Two ablations bracket the failure for anyone reproducing it: disabling skill injection establishes a flat floor, and imposing *premature* retirement causes active harm ([Library Drift, 2026](https://arxiv.org/abs/2605.19576)) — which is why retirement deserves as much design attention as admission.

## Admission, Evidence, and Retirement

A library with no admission rule grows at the rate the agent has ideas; with no retirement rule it grows until it stops working. Both rules must be mechanical, because both are judgments an agent will otherwise make in its own favour.

### What a new procedure must pass

Four parts, every one checkable without asking a model:

1. **It was run, on real work, at least once.** A procedure written from imagination is a draft, not a skill.
2. **A record of that run rides the same change that adds the skill.** Not "a record exists somewhere" — the same commit, so absence is loud where it can still be fixed.
3. **The record cites the intent the skill serves**, and that citation must resolve to something live. A fabricated citation resolves to nothing, which is what makes the check work.
4. **The record names the skill version and the outcome.** A skill *name* is not a version. "Used the release procedure" proves nothing after the procedure changed.

An estate that has run this gate for months reports the honest ceiling: it proves a record was committed and cites a live intent, never that the work described happened. Green means "ungoverned growth is now uncommittable" — nothing stronger, and worth a great deal, because it makes an invisible practice visible.

### Ratchet, never purge

Admission applies forward: new skills carry the record, and skills predating the rule are not retroactively refused. A compliance purge is the premature-retirement ablation — active harm — and it teaches authors to delete skills rather than document them.

### Retire on outcome, not on age

Track a per-skill contribution signal — did loading this skill correlate with better outcomes than not loading it — and retire below a threshold, under a bounded active cap that makes library size a budget rather than an accident. Both mechanisms were load-bearing in the measured fix; two others (canonicalization and guardrails) were subsumed by the rest. And never delete: the measured harness keeps every skill ACTIVE or DEPRECATED, because the evidence attached to a retired skill is what tells you whether retiring it was right.

### Bind evidence to a revision

Evidence binding is what makes any of the above decidable. A run record should carry the skill identity, the skill *version* (a content hash, not a name), the intent it served, the outcome, and a deterministic label per step — expected, skipped, wrong-version, or gap. Labels are computed, never stored as an agent's opinion, because a classification an agent writes about its own work is the thing being checked.

Absence is loud: a task claimed complete without a record is not closeable, in every mode, from day one. Mode is a ladder, not a switch — start in warn mode, where a dirty-but-present record prints its non-expected labels and exits clean; promote to fail mode only after a fleet measurement shows every existing receipted task is clean. A gate promoted by fiat gets disabled in a hurry on a bad day.

**A record is a claim, never an attestation.** Green means the agent typed the right names. What the machinery buys is narrower and real — a recordless use is loud, and a forged version or intent is inexpressible, because neither resolves to anything. Trace-level diagnostics are the same idea one level down: per-skill contribution scores, attribution verdicts, and router-engagement metrics make the failure visible *before* it reaches aggregate task scores.

## The Procedural Memory Spectrum

Six levels, with honest labels. Most teams run Levels 0–2 and describe themselves as being at Level 3.

| Level | Name | What exists | What breaks at this level |
|---|---|---|---|
| 0 | **Stateless** | Nothing. Each session re-derives the procedure from the code. | Every session pays full rediscovery; the same mistakes recur at the same rate. |
| 1 | **Single instruction file** | One always-loaded file of policy and procedure. | Context bloat (42% of surveyed repositories) and skill leakage (35%). Everything competes with everything on every task. |
| 2 | **Flat skill list** | Many skills; all names and descriptions in context; selection by description. | Selection, at scale: loading collapses from 49% to 31% to 16%, and metadata-only routing loses 31–44 points on a large pool. |
| 3 | **Routed skill list** | A maintained routing table naming which skill serves which situation, with edges verified by a check. | Silent edge rot. One operating estate measured 219 routing edges, 44 crossing a library boundary, and found **8 already dead** when the first check ran — nothing had verified them. |
| 4 | **Admission and evidence gates** | A skill cannot enter without a citing run record; runs are bound to a revision. | Bookkeeping without consequences, unless the labels drive retirement. A record nobody reads is a tax. |
| 5 | **Lifecycle governance** | Outcome-driven retirement, a bounded active cap, drift contracts validated against the live environment, per-skill contribution evidence. | Nothing structural — but the machinery only earns its cost once retrieval precision is a real constraint. |

Levels 3 through 5 are not maturity for its own sake: Level 3 makes dead routing visible, Level 4 makes ungoverned growth uncommittable, Level 5 makes drift and dead weight visible before they reach task scores. Level 5's costs are real — a lifecycle harness is a system, and a library of forty skills does not need one.

## Design Principles

1. **Write the trigger before the body.** The description is the only part read at selection time — write it in the words the task will arrive in, and test that the right prompts fire it.
2. **Keep the three tiers honest.** Metadata roughly 100 tokens; body under 5,000 tokens and under 500 lines; detail in `references/`, read on demand.
3. **Every skill ends with a check it can run.** A verification step that cannot fail is an instruction to proceed.
4. **Name the exit condition,** so following a procedure past the point it applies is a visible error.
5. **Admit with evidence, in the same change,** and make the refusal name the exact step that would satisfy it.
6. **Ratchet, never purge.** New skills must pass; existing ones are not retroactively refused.
7. **Retire on outcome, not age — and never delete.** Below-threshold contribution, under a bounded active cap, into a deprecated band that keeps the evidence.
8. **Route on the body once the pool outgrows the name list** — read the procedure, not the label.
9. **Keep the procedure out of the always-on file.** The test is "is this needed on every task?", not "is this useful?"

The six parts are cheap to template. A skeleton that carries all of them:

```markdown
---
name: release-cut
description: Cut and verify a release. Use when asked to release, tag, or
  publish a version, or when the release pipeline reports a stale lock.
---

## When this applies
Cutting a release, or recovering a release that failed mid-way.

## Procedure
1. Confirm the working tree is clean and the version file is bumped.
2. Acquire the release lock; if it is held, stop and report the holder.
3. Build, tag, and push the tag.
4. Run the verification below.

## Pitfalls
- The lock survives a crashed run; check age before forcing it.
- Tagging before the build passes leaves an unbuildable tag behind.

## Verification
Run `make verify-release` and report its exit code. Never report success
without it.

## Exit condition
Stop and re-derive if the tree contains changes not in the release plan.

## Retire when
The pipeline reports structured release errors directly.
```

## Evaluation: Real-World Systems

| System | Unit of procedure | How it loads | How it is selected | Admission / retirement |
|---|---|---|---|---|
| **Anthropic Agent Skills** ([spec](https://agentskills.io/specification), [docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)) | A directory with `SKILL.md` plus optional `scripts/`, `references/`, `assets/` | Metadata always (~100 tokens), body on activation (<5k recommended), resources on demand | Model decides from `name` + `description`; implicit or explicit invocation | None in the format; the format is deliberately unopinionated |
| **OpenAI Codex Skills** ([docs](https://developers.openai.com/codex/skills), [curated set](https://github.com/openai/skills)) | Same `SKILL.md` format; optional `agents/openai.yaml` for UI metadata, invocation policy, tool dependencies | Same progressive disclosure | Implicit by default; `allow_implicit_invocation: false` makes invocation explicit-only | Disable-without-delete and plugin-based distribution |
| **Gemini CLI skills** | `SKILL.md` in a project or user skills directory | Progressive disclosure | Explicit skill-activation interface — activation is a named action, not a model judgment | Reported in the benchmark as not supporting self-generated skills, consistent with explicit activation |
| **Cursor** ([rules](https://cursor.com/docs/context/rules)) | Rules in four types — always-on, auto-attached, model-decided, manual — plus `SKILL.md` skills | Rule type sets load timing; skills follow the shared format | Model decision or explicit reference, per rule type | Operator-managed; the rule types are the load policy |
| **MCP** ([spec](https://modelcontextprotocol.io/)) | Servers exposing tools and resources | Tool schemas load with the session; resources are fetched | Tool selection per call; no procedural layer | Not applicable — MCP carries capability, not procedure |
| **Community skill directories** ([example](https://github.com/VoltAgent/awesome-agent-skills)) | Thousands of contributed `SKILL.md` packages | Format-compatible across harnesses | The same metadata-only problem, at directory scale | Almost none. Reported ecosystem mean skill quality is 6.2/12 against 10.1/12 for curated benchmark skills |

The pattern is consistent: **the format converged, and the lifecycle did not.** `SKILL.md` is portable across half a dozen harnesses and the loading model is standardised. Missing everywhere is the part this document has spent its second half on — who decides a skill may enter, what evidence says it worked, and who decides it should go.

## Field Notes from an Operating Estate

Three dated observations from an estate running a governed skill library across three libraries.

**August 2026 — routing edges rot silently.** A check was written to walk every routing edge in the collection and ask whether its target existed. The first run found 219 edges, 44 of them crossing from one library into another, and **8 that resolved to nothing at all**. No agent had reported a problem. An agent routed to a skill that is not there does not fail loudly; it proceeds without the procedure, which is indistinguishable from a task that needed no procedure. A routing graph is a dependency graph, and an unverified dependency graph is already broken somewhere.

**August 2026 — an admission gate buys less than it looks like it buys.** The same estate made skill files uncommittable unless a run record rode the same change and cited a live intent node. After months of operation the honest reading is that the gate proves a record was committed, never that the work it describes happened. Its value is narrower and real: ungoverned growth becomes uncommittable, and a fabricated citation resolves to nothing, so it cannot be written at all. The gate's own documentation states the ceiling rather than hiding it.

**July 2026 — an instruction that inverted its own intent.** One standing instruction told agents that clarity mattered more than concision. The agents it governed read it as a standing licence to write long, and produced exactly what the instruction existed to prevent; the operator's complaint was that output ran long, carried material irrelevant to the decision at hand, and was dense with abbreviations that had to be looked up. The defect was structural rather than a wording slip — the instruction supplied the licence it was arguing against. The fix removed the length axis entirely and replaced it with one test: can the reader act from this message alone? A procedure can encode the same self-contradiction, and no amount of correct formatting will rescue it.

## Recommendations

**Short term — make the trigger work.** Rewrite every description that names a topic instead of a situation, and test that the prompts you expect to trigger a skill actually do.

**Medium term — make admission and evidence mechanical.** Add the four-part admission test, record runs with a content-hash skill version and computed per-step labels, and run the evidence gate in warn mode before promoting it.

**Long term — govern the lifecycle.** Track per-skill contribution and retire below a threshold under a bounded active cap, validate role-bearing assumptions against the live environment, and route on the body once a name list can no longer disambiguate the pool.

## The Hard Truth

The measured evidence is not encouraging: **skills are a strong idea with a fragile implementation, and most of the fragility is organisational rather than technical.**

Curated skills return +16.2 percentage points on average, and it degrades to nothing as the setting becomes realistic. Every degradation is a selection failure: the agent could not tell which skill was worth loading, or the retrieved content was noisy, or the right skill was lost among 80,000 others. The agent cannot write its own skills, ecosystem quality averages half a curated benchmark set's, and 91 of 100 surveyed repositories carry a configuration smell.

The uncomfortable conclusion is that a skill library is not a knowledge asset. It is a *retrieval system with a maintenance cost*: quality is set by the precision of its index and the discipline of its pruning, not the volume of its contents. Teams that accumulate documents get a library that grows while capability stays flat; teams that run a governed pipeline — trigger-tested on entry, evidence-bound per use, retired on measured contribution — get the +16.2 points, and keep them.

One correction is worth carrying. The folk wisdom that long instruction files destroy compliance did not survive controlled measurement: file size from 25 to 500 lines showed no detectable effect on adherence. What decayed was compliance *within* a session, non-monotonically, by roughly 5.6% per additional generated function — an effect identified during analysis rather than pre-specified. If that replicates, the lever is fresh context and short sessions, which argues for skills as a context-freshening device and not merely a context-saving one.

## Summary Checklist

- [ ] Every skill's `description` names a **situation**, not a topic, and has been tested against the prompts that should trigger it.
- [ ] Every skill carries an ordered procedure, its pitfalls, a **check that can fail**, an exit condition, and a retirement condition — inside the size budget (under 500 lines, body under roughly 5,000 tokens, detail in `references/`).
- [ ] A new skill cannot land without a run record in the same change, citing a resolvable intent and naming the skill's **content-hash version**, with computed per-step labels.
- [ ] The evidence gate started in warn mode and was promoted only after a fleet measurement showed every existing receipted task clean.
- [ ] Retirement is outcome-driven under a bounded active cap, into a deprecated band that is never deleted, and admission applies forward only.
- [ ] You can answer, for every skill: when did it last fire, and did it help?

## References

### Specifications and vendor documentation

- [Agent Skills specification](https://agentskills.io/specification) — required fields, layout, the three disclosure tiers, the 500-line guidance.
- [Agent Skills overview, Claude platform docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) — the three-tier token table and field constraints.
- [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) — the rationale for progressive disclosure.
- [Skills explained: Skills vs prompts, Projects, MCP, and subagents](https://claude.com/blog/skills-explained) — the context-device comparison.
- [Codex skills documentation](https://developers.openai.com/codex/skills) — invocation policy, enable/disable without delete, authoring guidance.
- [openai/skills](https://github.com/openai/skills) and [anthropics/skills](https://github.com/anthropics/skills) — curated reference skill sets.
- [Claude Code memory documentation](https://code.claude.com/docs/en/memory) — instruction-file sizing guidance.
- [AGENTS.md](https://agents.md/) — the cross-tool instruction-file convention.
- [Model Context Protocol](https://modelcontextprotocol.io/) — the tool layer skills sit beside.
- [Cursor rules](https://cursor.com/docs/context/rules) and [Copilot repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions) — rule types and always-on instruction files.

### Research

- [SkillsBench](https://arxiv.org/abs/2602.12670) — 84 tasks, 7,308 trajectories; +16.2pp curated, −1.3pp self-generated, 2–3 skills optimal, comprehensive −2.9pp.
- [How Well Do Agentic Skills Work in the Wild](https://arxiv.org/abs/2604.04323) — the selection and retrieval degradation ladder.
- [SkillRouter](https://arxiv.org/abs/2603.22455) — metadata-only versus body-aware routing on ~80,000 skills.
- [Library Drift](https://arxiv.org/abs/2605.19576) — the drift failure mode, its ablations, and the governance recipe.
- [Skill Drift Is Contract Violation](https://arxiv.org/abs/2605.10990) — role-dependent drift detection and localized repair.
- [Dynamic Agent Skills](https://arxiv.org/abs/2607.10113) — lifecycle taxonomy across self-evolving systems.
- [Instruction Adherence in Coding Agent Configuration Files](https://arxiv.org/abs/2605.10039) — structural nulls and within-session decay.
- [Configuration Smells in AGENTS.md Files](https://arxiv.org/abs/2606.15828) — the six-smell catalogue and skill-leakage prevalence.
- Replication artifacts: [Skill-Usage](https://github.com/UCSB-NLP-Chang/Skill-Usage), [SkillRouter](https://github.com/zhengyanzhao1997/SkillRouter), [Ratchet](https://github.com/amazon-science/Self-Evolving-Agents-Ratchet).

### Cross-references within this series

- [Context Engineering](context-engineering.md) — the context budget skills protect.
- [Memory and State Management](memory-and-state-management.md) — the memory taxonomy; this document adds the procedural tier.
- [Tool Design for LLM Agents](tool-design-for-llm-agents.md) — why tool schemas cost context permanently.
- [File-Based Memory for AI Systems](file-based-memory-for-ai-systems.md) — the declarative sibling of this problem.
- [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md) — the gate design used by admission and retirement.
- [Self-Improving Systems](self-improving-systems.md) — what the −1.3pp self-generation result bounds.

---

*Last reviewed: September 2026. Changed in this revision: new document — skills as selectable, evidence-bound procedures; measured degradation of skill utility under realistic selection; admission, evidence, and outcome-driven retirement. Length note: 5,085 prose words against the 3,000–5,000 target — the required Field Notes section was added after the target was set.*
