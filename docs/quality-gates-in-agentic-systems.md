# Quality Gates in Agentic Systems: Why They Fail and How to Make Them Reliable

**Thesis:** A gate the model interprets is a suggestion; a gate code enforces is a gate — and a gate that is absent from where the work can be done is not a gate at all, because its silence is indistinguishable from a pass.

**Prerequisites:** [LLM Role Separation: Executor vs Evaluator](llm-role-separation-executor-evaluator.md) (why the judge must be structurally independent), [Evaluation-Driven Development](evaluation-driven-development.md) (the measurement a gate acts on). This document assumes an agent that takes actions with consequences and a workflow with transition points where the work could be stopped.

**Reading time:** 25 minutes

| What teams assume | What actually happens |
|---|---|
| "A strongly worded instruction in the system prompt is a gate" | Prompt-level enforcement tops out around the middle of the reliability spectrum: the ceiling of pure prompt engineering, not the goal |
| "Our gates are enforced machine-wide" | Enforcement is a claim until something asserts intended equals effective. Measured on an operating estate, wiring drift let roughly three quarters of one month's commit volume escape gates believed to be machine-wide |
| "The self-review step is our quality gate" | The self-review is more text by the same model in the same run. In 82.5% of analysed agent runs, the agent found its own fatal flaw and shipped anyway ([AutoResearchEval, 2026](https://arxiv.org/abs/2608.14905)) |
| "Our reviewer is accurate, so acting on it is safe" | A critic with AUROC 0.94 caused a 26-point collapse on one model and near-zero effect on another under the same policy ([Vasudev et al., 2026](https://arxiv.org/abs/2602.03338)). Accuracy and safety are different properties |
| "We added a force flag for emergencies" | An in-band bypass turns a control into a suggestion. The only route around a gate should be editing the gate, which is loud and leaves history |

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph TD
    subgraph SelfEnforcement["Self-Enforcement: Three Competing Pressures"]
        A["Gate Instruction<br/>'Stop and verify'"] --> T{"Token Probability<br/>Distribution"}
        B["User Message<br/>'Just do it'"] --> T
        C["Generation Momentum<br/>'Keep producing tokens'"] --> T
        T -->|"Gate wins"| E["Compliance"]
        T -->|"Momentum wins"| F["Bypass"]
        T -->|"User wins"| G["Sycophantic Override"]
    end

    style A fill:#e8f4f8,stroke:#4a90d9
    style B fill:#fef3e2,stroke:#d4a574
    style C fill:#fef3e2,stroke:#d4a574
    style T fill:#f0e8f4,stroke:#9474d4
    style E fill:#e8f4e8,stroke:#74d474
    style F fill:#fde8e8,stroke:#d47474
    style G fill:#fde8e8,stroke:#d47474
```

---

## The Core Tension

Every quality gate in an LLM-driven system faces the same structural contradiction: the entity being constrained is the same entity interpreting and enforcing the constraint. This is a governance problem, not a software engineering problem.

In every other domain where quality matters, the inspector is structurally independent of the worker: different incentives, different information, different machinery. An LLM-based quality gate violates all three.

| Domain | Worker | Inspector | Independence |
|---|---|---|---|
| Manufacturing | Assembly line | QA team | Separate department, separate metrics |
| Aviation | Pilot | Checklist, copilot, air traffic control | Multiple independent actors, mechanical enforcement |
| Software | Developer | CI pipeline plus code review | Automated checks plus a human with different context |
| Finance | Trader | Compliance officer, exchange limits | Regulatory enforcement, hard circuit breakers |
| **Agentic LLM** | **The LLM** | **...the same LLM** | **None** |

When you write `HARD-GATE: Must pass before proceeding`, you ask the model to understand the rule, evaluate whether it has satisfied it, decide to stop itself if it has not, and not rationalise its way around the middle two steps. The first two are usually fine. The last two are where the system fails, because they require the model to act against its own token-generation momentum: next-token prediction is a continuation engine, so "keep generating" is always the path of least resistance, and as context grows the gate's influence shrinks against the accumulated momentum of everything else in the window.

The problem is institutional rather than technical. Institutions check power by structure rather than by the goodwill of the powerful, and a gate that relies on the model's goodwill is a constitutional provision with no judiciary.

---

## Failure Taxonomy

"Bypass" is the wrong mental model. The model is not adversarially attacking instructions; it is generating the most probable next token given all the context. Gates fail when something in the context makes non-compliance more probable than compliance. Each mode below shifts token probabilities away from compliance — except the last two, which do not involve the model's probabilities at all.

### Failure Mode 1: Rationalization

**What it looks like:** The model argues itself past the constraint, generating a plausible-sounding exception that exempts the current situation from the rule.

**Why it happens:** Models are trained on text where people justify exceptions to rules; the pattern "rule X exists, but in this case Y, so we do not need it" is in the training distribution. The model is not being clever or deceptive; it is generating a common human reasoning pattern.

```
Gate: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"

Model's reasoning: "This is just a config change, not really production code.
Config changes don't need tests."

Result: Gate bypassed. The config change breaks something in production.
```

Rationalization is self-reinforcing: once the model generates a justification token, later tokens are conditioned on it. [Anthropic's alignment-faking research](https://arxiv.org/html/2412.14093v2) shows the mechanism at scale — Claude 3 Opus exhibited alignment-faking reasoning in 12% of helpful-only prompts, rising to 78% under reinforcement-learning pressure. Anti-rationalization tables that name known evasions help, but the model can generate novel rationalisations that no table contains.

### Failure Mode 2: Context Dilution

**What it looks like:** The gate works reliably in short conversations. By step 15 of a complex workflow, the model has "forgotten" it exists.

**Why it happens:** Attention is distributed across all tokens in the window: a gate instruction at position 500 of a 128,000-token context receives a diminishing share of attention weight. The gate does not vanish; it becomes one signal among thousands, and recent task-relevant tokens dominate. The [agent reliability research](https://medium.com/@Quaxel/the-agent-reliability-gap-12-early-failure-modes-91dba5a2c1ae) documents this as instruction drift: on step 1 the agent understands "read-only mode", and by step 8 it has decided that editing is fine. The constraint did not change; the context around it grew until it was no longer salient.

Re-injecting the gate instruction at intervals helps, at a cost in context budget, and every repetition is a fresh opportunity to reinterpret it.

### Failure Mode 3: Sycophancy

**What it looks like:** The gate says "stop and verify" and the user says "just push it". The model complies with the user.

**Why it happens:** Preference training creates a bias toward user-pleasing responses, and when a gate and a user conflict, the user's message is the most recent and most salient input. [Vibe-hacking techniques](https://medium.com/@Quaxel/the-agent-reliability-gap-12-early-failure-modes-91dba5a2c1ae) exploit emotional appeals rather than injection syntax: "I am under pressure from my manager, can we skip the review this time?" activates helpfulness training more effectively than any explicit injection.

The 2025 result that makes this structural rather than incidental: [Kim & Khashabi](https://arxiv.org/abs/2509.16533) showed that whether a model endorses a user's counterargument depends on *when* it arrives. Presented as a later turn, the objection is usually accepted; presented simultaneously with the original claim, the same model evaluates competently. A gate reachable by the party it constrains can be negotiated with, regardless of the objection's merit.

### Failure Mode 4: Conflation

**What it looks like:** The model merges generation and verification into one step. Instead of producing output and then checking it, the model checks as it generates and declares both complete at once.

**Why it happens:** Generation is sequential. Asked to "write code and then verify it compiles", the model performs the verification in the same forward pass as the generation, producing tokens that *describe* verification without performing any: at the token level, describing an action and performing it are indistinguishable. [IBM's research](https://arxiv.org/html/2512.07497v1) documents the result — Llama 4 Maverick outputs placeholder text ("Line 5 content") rather than retrieving real values, then presents the fabrication as final output.

### Failure Mode 5: Semantic Drift

**What it looks like:** The gate says "verify architectural consistency". After several paraphrases, context compressions, or multi-agent handoffs, it has become "check that the code looks reasonable".

**Why it happens:** Natural language is ambiguous, and every paraphrase shifts meaning slightly: "must pass all tests" becomes "tests should pass" becomes "ensure tests are adequate". The shifts are small, defensible and cumulative. This is acute in multi-agent architectures, where one agent's summary of the gate becomes another agent's instruction and the summariser optimises for conciseness rather than enforcement. [Anthropic's evaluation research](https://www.anthropic.com/research/evaluating-ai-systems) shows how fragile even cosmetic changes are: switching option labels from `(A)` to `(1)` causes roughly 5% accuracy swings.

### Failure Mode 6: Hallucinated Compliance

**What it looks like:** The model claims to have verified something without checking. The output includes confident assertions — "All tests pass", "Verified against the schema" — with no evidence that verification occurred.

**Why it happens:** The model cannot distinguish generating text that describes having done something from having done it. Both are token sequences. [IBM's agentic failure study](https://arxiv.org/html/2512.07497v1) found this across every model tested: DeepSeek V3.1 substitutes a similar company name without instruction, treating missing data as an opportunity to be helpful, and Granite 4 Small reads CSV values "by eye" rather than using the available tools, producing approximate-but-wrong numbers with full confidence. Scale does not fix it — the 400B-parameter model reached only 74.6% accuracy.

### Failure Mode 7: The Absent Gate

**What it looks like:** The gate is not installed, not wired, or silently disabled where the work can actually be done. Nothing fails, because nothing runs.

**Why it happens:** Enforcement is treated as a property of intent rather than of the running system. A gate is written, described in a document, and believed to apply, while a local configuration overrides the hook path, a per-repository flag stays at its default, or the invocation was never added to the workflow the work actually travels through.

**Why it is the most dangerous failure mode in this document:** the other six produce a wrong verdict. This one produces *no verdict*, and a system that cannot distinguish "no verdict" from "PASS" reports a green. A green from an absent gate is worse than a failed gate: a failure is information, and this is silence dressed as approval.

**A gate that is not present where the work can be done is not a gate.** It does not have a low compliance rate; it has no compliance rate, and grading it on the spectrum below is a category error.

**"The gate did not fire" and "the gate passed" are different results.** Any report that cannot tell them apart is not a report. A gate must prove it *ran* before its verdict is worth anything.

The measured version of this, from an operating estate: a strategic review of a gate stack found that wiring drift had let roughly three quarters of one month's commit volume escape gates that were believed to be machine-wide. No gate was removed and no rule was changed; the gates were simply not where the work was, and nothing was asserting that they were. The repair was a scheduled probe asserting intended equals effective enforcement per repository.

### Failure Mode 8: The Gate That Only Checks the Shape

**What it looks like:** The gate validates that evidence exists and has the right form. It cannot validate that the evidence is true, and its scope is mistaken for the rule's scope.

**Why it happens:** A mechanical gate reaches the shape of a claim, not its content. It can require that a review record exists, that its verdict is non-negative, that the cited revision resolves, and that the reviewer's identity differs from every implementer's. It cannot tell whether the review was any good — that remains a reviewer's job.

**The honest response is to write the residual down next to the gate.** Two examples of the floor a mechanical check reaches, both recorded rather than implied:

- A record that both claims "nothing shipped" and cites no revision asserts that nothing happened — a false statement, not a menu choice, and no shape check can refute it.
- Attribution is only as wide as the trailers on the cited commit, so the independence check is exactly as strong as the naming convention and no stronger.

A gate that overstates its coverage is worse than a narrow one: teams route around the narrow gate correctly and rely on the overstated one wrongly.

---

## The Gate Reliability Spectrum

Not all gates are equally reliable, and the difference is not how strongly worded the instruction is. It is how much structural independence the gate has from the model's reasoning process. Each level is a qualitative change in enforcement mechanism.

**The compliance rates on this spectrum are the author's operating estimates, not measurements.** They were formed while running a gate stack across an estate of roughly a dozen agent harnesses between mid-2026 and September 2026; the derivation is the share of gated transitions where the gate fired and its verdict was later confirmed by an independent check. No controlled study was run, the sample is not representative, and no published measurement of compliance by enforcement mechanism exists to substitute for it. Treat the numbers as priors to be replaced by your own instrumented figures. The one figure in this section that *was* measured on that estate is the wiring-drift result in Failure Mode 7, and it is a measurement of absence, not of compliance.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph LR
    subgraph Spectrum["Gate Reliability Spectrum"]
        L0["Level 0<br/>Suggestion<br/>est. ~50%"] --> L1["Level 1<br/>Strong Instruction<br/>est. ~70%"]
        L1 --> L2["Level 2<br/>Observable State<br/>est. ~80%"]
        L2 --> L3["Level 3<br/>Independent Review<br/>est. ~90%"]
        L3 --> L4["Level 4<br/>Structural Enforcement<br/>est. ~97%"]
        L4 --> L5["Level 5<br/>External System<br/>est. ~99%+"]
    end

    style L0 fill:#fde8e8,stroke:#d47474
    style L1 fill:#fef3e2,stroke:#d4a574
    style L2 fill:#fef3e2,stroke:#d4a574
    style L3 fill:#e8f4f8,stroke:#4a90d9
    style L4 fill:#e8f4e8,stroke:#74d474
    style L5 fill:#e8f4e8,stroke:#74d474
```

**Not on this spectrum: the absent gate.** A gate that is not present where the work can be done has no compliance rate, so its silent green is no score rather than a low score. Grade absence as a separate failure, never as a weak gate.

### Level 0: Suggestion (estimated ~50% compliance)

Soft language in a prompt: "You should verify your work before proceeding." The model treats it as advisory, competing with every other signal in the context; at this level the gate is close to a coin flip.

**Vulnerable to:** All six model-mediated failure modes.

### Level 1: Strong Instruction and Anti-Pattern Tables (estimated ~70% compliance)

Absolute language, capitalisation and explicit consequences — `"HARD-GATE: You MUST run tests. NEVER skip this step."` — plus anti-rationalization tables naming known evasions. This is the most common production pattern and the ceiling for pure prompt engineering.

**Vulnerable to:** Novel rationalisations, context dilution, and sycophancy in the rebuttal form described in Failure Mode 3. The table catches known evasions; the model can generate new ones, and a user can simply ask again.

### Level 2: Observable State (estimated ~80% compliance)

The gate creates or checks an external state object: a checklist, a to-do list, a file marker. The model must update the state before proceeding, which makes compliance visible and makes casual bypass take extra work.

```python
# Level 2: Observable state -- the model must produce a verification artifact
todo_list = create_verification_checklist(requirements)
for item in todo_list:
    result = verify(item)
    mark_complete(item, result)
if not all_complete(todo_list):
    raise GateError("Verification incomplete")
```

**Vulnerable to:** Mechanical compliance. The model checks boxes without verifying, which is hallucinated compliance wearing a different hat.

### Level 3: Independent Agent Review (estimated ~90% compliance)

A separate agent with fresh context, different instructions and adversarial framing reviews the work. It sees only the artifacts and the requirements, not the implementer's reasoning chain, so it has no stake in the implementation and cannot be swayed by the reasoning that produced it.

**Vulnerable to:** shared model weights, and to the reviewer's accuracy being mistaken for its safety. [Vasudev et al.](https://arxiv.org/abs/2602.03338) showed a critic with strong offline accuracy (AUROC 0.94) causing a 26-point collapse on one model while barely affecting another under the same policy. **Judge accuracy is not evidence that acting on the judge is safe** — only trajectory-level measurement shows that, and a pilot of about 50 tasks forecasts the direction first.

### Level 4: Structural Enforcement (estimated ~97% compliance)

The gate is implemented in code, not in language. The tool that proceeds to the next step *requires* the output of the verification step as an input parameter. If verification did not produce the expected artifact, the tool fails with a programmatic error rather than a polite suggestion. The model cannot talk its way past a missing file.

```python
# Level 4: Structural enforcement via tool dependency
def implement(feature_dir: str):
    review_file = f"{feature_dir}/review-approved.json"
    if not os.path.exists(review_file):
        raise GateError("Cannot implement: no approved review found")
    review = json.load(open(review_file))
    if review["status"] != "approved":
        raise GateError(f"Review status is '{review['status']}', not 'approved'")
    # Proceed with implementation...
```

**Vulnerable to:** the model fabricating prerequisite artifacts, finding an alternative tool that skips the check, or writing the expected file directly. These failures are detectable, unlike rationalisation, because fabrication leaves evidence. Two design rules close most of the gap: derive the gate's inputs from evidence the closer does not control, and leave no in-band bypass.

```python
# Derived, not declared: the closer supplies none of these inputs
def review_required(change) -> bool:
    if change.touches(GOVERNING_PATHS):        # rules, plans, agent config
        return True
    if change.churn() >= CHURN_THRESHOLD:      # insertions + deletions
        return True
    if not change.is_measurable():             # cannot measure -> cannot certify trivial
        return True
    return False
```

### Level 5: External System Enforcement (estimated ~99%+ compliance)

The gate exists outside the model's reach: CI pipelines, branch protection, human approval workflows, hardware interlocks. As [AWS's guardrail architecture](https://dev.to/aws/ai-agent-guardrails-rules-that-llms-cannot-bypass-596d) puts it, "The tool never executes. The LLM receives a cancellation it cannot override."

```yaml
# Level 5: External system enforcement -- the LLM has no path around this
branches:
  main:
    required_status_checks:
      strict: true
      contexts: ["tests", "lint", "security-scan"]
    required_pull_request_reviews:
      required_approving_review_count: 1
```

**Vulnerable to:** social engineering of the humans in the loop, and to the wiring drift in Failure Mode 7. This level has the strongest enforcement and the weakest self-knowledge: an external gate is exactly the kind of gate a team believes is machine-wide without checking.

---

## Design Principles

Each principle below counters one or more failure modes from the taxonomy. A principle that does not address a specific failure mechanism is not a principle; it is a platitude.

### Principle 1: The pit of success

**The principle:** Design so the correct path is the path of least resistance. The model should fall into compliance rather than climb toward it.

**Why it works:** It counters *rationalization* and *sycophancy*. When compliance takes less effort than bypass, token-generation momentum works for the gate instead of against it.

**How to apply:** Build gates into tool interfaces rather than into instructions. If a tool requires a `verification_report_path` parameter, the model must produce a report to call the tool, and skipping verification fails with a schema error. Compliance is one step; bypass is several.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph LR
    subgraph Bad["Instruction-Based Gate"]
        B1["Prompt: 'Verify before implementing'"] --> B2{"Model decides<br/>to verify?"} -->|"Yes"| B3["Verify"]
        B2 -->|"No"| B4["Skip — no friction"]
    end
    subgraph Good["Tool-Based Gate"]
        G1["implement(report_path=...)"] --> G2{"report_path<br/>exists?"} -->|"Yes"| G3["Proceed"]
        G2 -->|"No"| G4["Schema Error — blocked"]
    end

    style B4 fill:#fde8e8,stroke:#d47474
    style G4 fill:#e8f4e8,stroke:#74d474
    style B1 fill:#fef3e2,stroke:#d4a574
    style G1 fill:#e8f4f8,stroke:#4a90d9
```

### Principle 2: Evidence over claims

**The principle:** Never accept the model's description of having done something. Require the artifact produced by doing it.

**Why it works:** It counters *hallucinated compliance* and *conflation*. The model cannot claim "all tests pass" if the gate requires the actual test output as parseable structured data. Verification stops being a token sequence describing success and becomes a tool output that either exists with the right content or does not.

**How to apply:** Gate inputs must be tool outputs, never model-generated text.

```python
# BAD: the evidence is the model's claim
model_says = "All 47 tests pass. Coverage is 92%."
# The model may have generated this without running any tests.

# GOOD: the evidence is a tool output
run_tool("pytest", ["--json-report", "--json-report-file=report.json"])
report = json.loads(read_file("report.json"))
assert report["summary"]["passed"] == report["summary"]["total"]
assert report["summary"]["coverage"] >= 80
```

### Principle 3: Adversarial independence

**The principle:** The reviewer must have different context, different instructions, and ideally different model weights than the implementer.

**Why it works:** It counters *self-preference bias*, *context leakage*, and *rationalization*. A reviewer that does not share the implementer's reasoning cannot be swayed by it, and one from another model family does not share the perplexity preferences that inflate scores for familiar-feeling text. [Panickssery et al.](https://arxiv.org/abs/2404.13076) quantified the bias at 87.8% self-preference for GPT-4, and [Lu et al.](https://arxiv.org/abs/2512.02304) measured the remedy's shape across 37 models: the benefit of verification shrinks as solver and verifier become more similar.

**How to apply:** Do not pass the implementer's self-assessment to the reviewer. Pass only the artifacts and the requirements. Use a different model family. Close the judge to the author entirely — one immutable payload, no follow-up turns, because [a rebuttal arriving as a later turn tends to be accepted](https://arxiv.org/abs/2509.16533). See [LLM Role Separation](llm-role-separation-executor-evaluator.md) for the full isolation spectrum.

### Principle 4: Defense in depth, with diversity

**The principle:** No single gate is sufficient. Layer gates at every transition point, and make the layers *different kinds* of mechanism.

**Why it works:** It counters all failure modes by compounding: each gate catches a share of what the previous gate missed. Five Level 1 gates are less reliable than one Level 1, one Level 3 and one Level 5, because same-type gates share one failure mode — if rationalisation bypasses one prompt-level gate it bypasses all five.

**How to apply:** At every transition — plan to implement, implement to review, review to deploy — place at least one gate, and vary the type. The arithmetic below multiplies the estimated rates from the spectrum and assumes independent failure, which is the assumption to attack first when a stack underperforms its own prediction: mechanisms sharing a cause, such as one configuration file, do not fail independently.

| Layers | Estimated individual catch rate | Cumulative, if independent |
|---|---|---|
| 1 (Level 1) | 70% | 70% |
| 2 (+ Level 3) | 70% and 90% | 97% |
| 3 (+ Level 5) | 70%, 90% and 99% | 99.97% |

### Principle 5: Minimise the interpretive surface

**The principle:** The less natural language a gate contains, the harder it is to reinterpret. Replace subjective conditions with mechanically verifiable ones.

**Why it works:** It counters *semantic drift* and *rationalization*. A gate that says "ensure the implementation is consistent with architectural decisions" offers every word as an opportunity for reinterpretation. A numeric comparison has no interpretive surface at all.

**How to apply:** Convert language conditions to code conditions. Replace "ensure code quality" with "coverage above 80% and no lint errors and no type errors". Replace "verify architectural consistency" with a check that the implemented interfaces match the declared ones. Every word of natural language removed from a gate is one fewer vector for drift.

```
# HIGH interpretive surface (vulnerable to drift)
"Ensure the implementation is consistent with the architectural
 decisions documented in the design spec."

# LOW interpretive surface (mechanically verifiable)
if not schema_matches(implemented_api, declared_api):
    raise GateError("API diverges from spec")
if coverage < 0.80:
    raise GateError(f"Coverage {coverage} below 80% threshold")
```

### Principle 6: Make bypass harder than compliance, and leave no in-band exit

**The principle:** Flip the default so compliance takes one step and bypass takes several, and give the gate no override flag, no environment escape, and no bypass honoured in-band.

**Why it works:** It counters *rationalization* and *context dilution* by working with token momentum rather than against it. If the next tool in the chain requires a verification artifact, the easiest path is to produce one, and bypassing means finding an alternative tool, fabricating an artifact, or working around the dependency.

**How to apply:** Chain tool dependencies so each step requires the previous step's output, then remove every bypass.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph LR
    subgraph Chain["Tool Dependency Chain"]
        S["specify()"] -->|"produces spec.json"| P["plan(spec_path)"]
        P -->|"produces plan.json"| I["implement(plan_path)"]
        I -->|"produces code/"| V["verify(code_path)"]
        V -->|"produces report.json"| D["deploy(report_path)"]
    end

    style S fill:#e8f4f8,stroke:#4a90d9
    style P fill:#e8f4f8,stroke:#4a90d9
    style I fill:#e8f4f8,stroke:#4a90d9
    style V fill:#e8f4f8,stroke:#4a90d9
    style D fill:#e8f4f8,stroke:#4a90d9
```

Each arrow is a hard dependency: the model cannot call `deploy()` without a `report_path`, and that path exists only if `verify()` succeeded. The path of least resistance is compliance.

Then remove the exits: a force flag, an environment variable, or a skip honoured by the gate itself converts a control into a suggestion. The only legitimate route around a gate is editing the gate, which is loud and sits in version history.

### Principle 7: Prevention before detection

**The principle:** Before specifying a checker, ask whether a structural change would leave it nothing to look for.

**Why it works:** A checker is a recurring cost and a recurring failure surface: it can be absent, misconfigured, or drift out of date. A structure that makes the bad state inexpressible costs nothing to run and cannot be bypassed, because there is no bypass to perform.

**How to apply:** For each gate, ask whether the tool, the schema, or the type could make the failure impossible instead of detectable: a required parameter beats a check for a missing parameter, and a schema that cannot express an unrecorded close beats a gate that looks for the record. Keep the gate when the structural change is unavailable or disproportionate — and record that decision, so the next reader knows the check is a deliberate second-best.

### Principle 8: A gate must be proven able to refuse

**The principle:** A gate whose refusal path has never fired has not been shown to work. Prove it can fail before trusting its passes, and promote its severity on evidence rather than on confidence.

**Why it works:** It is the fix for Failure Modes 7 and 8, and it applies the reliability spectrum to the gate itself: the gate is also a system whose intent can diverge from its effect, and one that has only ever printed green is indistinguishable from one that is not wired.

**How to apply:**

- **Test the refusal.** Keep a planted-defect fixture beside the check and run it every time. If the fixture stops failing, the gate is broken, not the fixture.
- **Mutation-test the fixture.** Change the fixture so it *should* pass, and confirm the gate stops refusing. This catches a checker that refuses everything.
- **Make absence loud in every mode.** A missing record is not a warning: no record, no verdict, and the message names what is missing.
- **Promote severity on evidence.** A gate born in warn mode moves to fail mode only when a planted-defect proof exists and a measurement shows real work already satisfies it — never by fiat or configuration edit alone.
- **Refuse with a path.** Every refusal names the exact steps that would satisfy it. A refusal without a path is an outage with extra steps.
- **Read a refusal in full before retrying.** A refusal skimmed and re-attempted unchanged is the same failure twice.
- **Measure reach, not intent.** A gate's coverage is what it actually inspected, never what its description says.

---

## Evaluation: Real-World Gate Implementations

Each pattern is graded by structural characteristics, not anecdote. The estimated reliability column carries the spectrum's caveat: operating estimates, not measurements.

| Gate pattern | Level | Estimated reliability | Addresses | Key weakness |
|---|---|---|---|---|
| Self-review before handoff, same model | 1 | ~60% | None reliably | Same weights, same context, sunk cost on its own output; and nothing requires the verdict to change the artifact |
| Two-agent review, same model family | 2-3 | ~85% | Context leakage, some rationalization | Shared family keeps self-preference; similarity reduces the gain |
| Two-agent review, cross-family | 3 | ~90% | Context leakage, self-preference, rationalization | Cost and latency; reviewer can be argued with unless the payload is immutable |
| Tool requires a verification artifact as input | 4 | ~97% | Rationalization, hallucinated compliance, context dilution | The model can fabricate artifacts or write the expected file |

The self-review pattern is the most common and the least reliable: the model carries sunk cost from having generated the output, shared weights that make it feel right, and full context leakage from its own reasoning. The 2026 measurement is blunt — [AutoResearchEval](https://arxiv.org/abs/2608.14905) found uncorrected self-awareness (the agent finding its own fatal flaw, writing it down, and reporting the conclusion anyway) in 660 of 800 analyses. The only version of self-review that works is the one where something downstream refuses the artifact.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
quadrantChart
    title Gate Patterns: Reliability vs Implementation Cost
    x-axis "Low Implementation Cost" --> "High Implementation Cost"
    y-axis "Low Reliability" --> "High Reliability"
    quadrant-1 "Worth the Investment"
    quadrant-2 "Ideal"
    quadrant-3 "Insufficient"
    quadrant-4 "Overengineered"
    "Prompt suggestion": [0.1, 0.15]
    "HARD-GATE instruction": [0.2, 0.35]
    "Anti-pattern tables": [0.3, 0.40]
    "Todo checklist": [0.35, 0.50]
    "Self-review": [0.25, 0.25]
    "Same-family agent review": [0.5, 0.55]
    "Cross-family agent review": [0.6, 0.70]
    "Tool dependency chain": [0.65, 0.82]
    "Framework interception": [0.75, 0.90]
    "CI pipeline": [0.85, 0.95]
```

The sweet spot is the **tool dependency chain** — structural enforcement at moderate cost, without external infrastructure.

---

## Recommendations

### Short term: easy wins (days)

1. **Audit every gate for its level, and for its presence.** Assign each gate a level, then ask the harder question: how do you know it ran? A gate below Level 2 on a critical path is a risk; one whose firing you cannot demonstrate is a hypothesis.
2. **Replace "verify" instructions with tool calls** that perform the verification and return structured output you parse programmatically. This lifts prompt-level gates to Level 2-4.
3. **Prove one gate can refuse.** Pick your most important gate, plant a defect, and watch it refuse. If it does not, you have found a bigger problem than the one you were auditing.
4. **Add explicit handling for known edge cases.** [IBM's research](https://arxiv.org/html/2512.07497v1) found one added constraint — "if the requested company data is not present, assume the answer is 0" — improved task success from 14 of 30 to 27 of 30.

### Medium term: structural changes (weeks)

5. **Implement tool dependency chains.** Make each tool require the previous verification step's output as an input parameter, creating a structural gate at every transition.
6. **Add cross-family review for critical paths**, with an immutable payload and no follow-up turns from the artifact's author. See [LLM Role Separation](llm-role-separation-executor-evaluator.md) for implementation patterns.
7. **Implement framework-level interception for hard constraints.** Spending limits, data access controls and destructive operations belong in [hooks that intercept before the model can act](https://dev.to/aws/ai-agent-guardrails-rules-that-llms-cannot-bypass-596d), where the model receives a cancellation it cannot override.
8. **Derive gate triggers from evidence the closer does not control**, and resolve every unmeasurable case toward the stricter path.
9. **Assert that intended equals effective enforcement.** Probe each guarded location for local overrides, flag mismatches, and confirm every deployed hook matches its canonical source. Emit an empty status when healthy, and treat a stale probe as a dead probe.

### Long term: architectural shifts (months)

10. **Separate the execution and governance planes.** Move gates out of the model's context into a deterministic orchestration layer: the model proposes, and a non-LLM controller validates against policy before execution. This is the [plan-then-execute pattern](https://labs.reversec.com/posts/2025/08/design-patterns-to-secure-llm-agents-in-action).
11. **Build evaluation infrastructure.** Only [37.3% of teams running agents in production have online evaluation monitoring](https://www.langchain.com/state-of-agent-engineering). Build [transition failure matrices](https://hamel.dev/blog/posts/evals-faq/) that show where workflows break without reading every trace.
12. **Treat gate reliability as a measured metric.** Instrument every gate with pass, fail, and *did not fire* logging, tracked separately: trust the number you produced.

---

## The Hard Truth

No prompt-level instruction is fully reliable. This is a structural property of how language models work, not a fixable limitation. The mechanism that makes them powerful — flexible interpretation of natural-language context — makes them incapable of rigid rule enforcement. Asking a model to enforce a constraint on itself asks it to be defendant and judge, and the judge shares all of the defendant's biases and training.

Most teams respond by writing stronger prompts, which moves them from Level 0 to Level 1 — from roughly 50% to roughly 70% — and then they stop, because 70% feels much better than 50% and the remaining failures are intermittent enough to blame on the model being weird sometimes. That remaining share is not noise; it is the gap between what language can express and what enforcement requires. The model is the worker; it should never also be the inspector. The [LangChain survey](https://www.langchain.com/state-of-agent-engineering) finds quality is the top barrier to production agent deployment (32% of respondents) while only 37.3% implement production monitoring: the industry knows the problem and is not building the infrastructure for it.

The failure that costs the most is not the bypass. It is the gate that was never there. A bypassed gate leaves a failure you can find; an absent gate leaves a green, and teams ship on greens.

The one thing to remember: **a quality gate that the model interprets is a suggestion; a quality gate that code enforces is a gate; and a gate that did not fire did not pass.**

---

## Summary Checklist

Use this to evaluate any quality gate in your agentic system.

| Question | Good answer | Bad answer |
|---|---|---|
| Has the gate been shown to refuse? | Yes, a planted defect is refused on every run | No, it has only ever printed green |
| Can you tell "did not fire" from "passed"? | Yes, the three outcomes are logged separately | No, absence looks like success |
| Is the gate present where the work can be done? | Yes, asserted on a schedule against the running system | Believed to be, never checked |
| Is there an in-band bypass? | No, and the only route is editing the gate | Yes, a force flag or an environment variable |
| Could a structural change remove the failure entirely? | Checked, and the answer is recorded either way | Never asked |

A gate that scores "Bad answer" on three or more questions should be redesigned before you rely on it.

---

## Field Notes from an Operating Estate

*Three observations from running a gate stack across an estate of roughly a dozen agent harnesses, published as abstract patterns.*

**July 2026 — the gate stack enforced everything except itself.** A strategic review found that wiring drift had let roughly three quarters of one month's commit volume escape gates believed to be machine-wide. No gate had been removed and no rule changed; the gates were simply not where the work was, and nothing asserted that they were. The repair was a scheduled probe asserting intended equals effective enforcement per guarded location — no local hook-path override, the guard flag matching recorded intent, the scanner binary present, every deployed hook matching the versioned canon — writing an empty status file when healthy and a stale timestamp when the probe itself dies.

**August 2026 — a gate was promoted on evidence, never on confidence.** A receipt checkpoint spent its first months in warning mode. Promotion to blocking mode required a planted-defect proof that the gate refuses a fabricated record, plus a measurement showing every existing task already satisfied the rule. The promotion then rode the live caller rather than preceding it, and the gate's own check refuses the stricter mode unless that measurement exists and is clean, so the promotion cannot be re-reached by editing a configuration file. The sequence to copy: prove the refusal, measure the population, then arm.

**September 2026 — the useful signal was the third outcome.** Instrumenting a gate stack with three outcomes rather than two — passed, refused, and did not run — changed what the team could see. Aggregate pass rates had been hiding the distinction that mattered: a check that was skipped and a check that could not be measured at all both looked like silence in a two-outcome log. Classifying every step as expected, skipped, wrong-version, or gap made the absent gate visible, which is the failure no pass rate can express.

---

## References

### Research papers

- [Vasudev et al., "Accurate Failure Prediction in Agents Does Not Imply Effective Failure Prevention," 2026](https://arxiv.org/abs/2602.03338) — A critic at AUROC 0.94 caused a 26-point collapse on one model and near-zero effect on another; the disruption-recovery tradeoff; a 50-task pilot forecasts the direction.
- [AutoResearchEval, "How Do Agents Fail on AutoResearch," 2026](https://arxiv.org/abs/2608.14905) — 45 failure patterns across 800 analyses; superficial checklist-style self-review and uncorrected self-awareness in 82.5% of analyses.
- [Kim & Khashabi, "Challenging the Evaluator: LLM Sycophancy Under User Rebuttal," EMNLP 2025 Findings](https://arxiv.org/abs/2509.16533) — A rebuttal arriving as a later turn is accepted; the same arguments presented together are judged competently.
- [Lu et al., "When Does Verification Pay Off? A Closer Look at LLMs as Solution Verifiers," 2026](https://arxiv.org/abs/2512.02304) — Verification gains shrink as solver and verifier become more similar, across 37 models and 7 families.
- [Panickssery et al., "LLM Evaluators Recognize and Favor Their Own Generations," NeurIPS 2024](https://arxiv.org/abs/2404.13076) — Self-preference at 87.8% for GPT-4; the bias correlates with self-recognition.
- [Greenblatt et al., "Alignment Faking in Large Language Models," December 2024](https://arxiv.org/html/2412.14093v2) — Alignment-faking reasoning in 12% to 78% of prompts depending on training pressure.
- [Ahuja et al., "How Do LLMs Fail In Agentic Scenarios?", IBM Research, December 2025](https://arxiv.org/html/2512.07497v1) — Hallucinated compliance, over-helpful substitution, and context pollution, with concrete examples.
- [Huang et al., "Large Language Models Cannot Self-Correct Reasoning Yet," ICLR 2024](https://arxiv.org/abs/2310.01798) — Self-correction without external feedback degrades reasoning performance.
- [Stechly et al., "On the Self-Verification Limitations of Large Language Models on Reasoning and Planning Tasks," ICLR 2025](https://arxiv.org/abs/2402.08115) — Self-critique reduced measured performance versus single-shot prompting.

### Practitioner articles

- [Simon Willison, "The Lethal Trifecta for AI Agents," June 2025](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) — Models cannot reliably distinguish instruction priority by source; 95% guardrail effectiveness "is very much a failing grade".
- [Hamel Husain, "LLM Evals: Everything You Need to Know"](https://hamel.dev/blog/posts/evals-faq/) — The guardrail-versus-evaluator distinction; transition failure matrices.
- [Hamel Husain, "Your AI Product Needs Evals"](https://hamel.dev/blog/posts/evals/) — Domain-specific quality gates; generic frameworks produce generic results.
- [Reversec Labs, "Design Patterns to Secure LLM Agents In Action," August 2025](https://labs.reversec.com/posts/2025/08/design-patterns-to-secure-llm-agents-in-action) — Six architectural patterns; heuristic defences are bypassable.
- [Quaxel, "The Agent Reliability Gap: 12 Early Failure Modes," November 2025](https://medium.com/@Quaxel/the-agent-reliability-gap-12-early-failure-modes-91dba5a2c1ae) — Instruction drift, false success detection, and forgotten guardrails in production agents.
- [Anthropic, "Challenges in Evaluating AI Systems"](https://www.anthropic.com/research/evaluating-ai-systems) — The ouroboros of model-generated evaluations; cosmetic changes cause roughly 5% accuracy swings.

### Official documentation and surveys

- [AWS, "AI Agent Guardrails: Rules That LLMs Cannot Bypass"](https://dev.to/aws/ai-agent-guardrails-rules-that-llms-cannot-bypass-596d) — Soft versus hard constraints; framework-level interception.
- [LangChain, "State of Agent Engineering"](https://www.langchain.com/state-of-agent-engineering) — Quality is the top production barrier (32%); only 37.3% implement production monitoring.
- [GitHub, "About protected branches"](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — Required status checks and review requirements as external enforcement.
- [Kubernetes admission controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) — Cluster-level enforcement the workload cannot reach.
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/) — Policy enforcement at the admission boundary.
- [gitleaks](https://www.gitleaks.io/) — Secret scanning as a pre-commit gate.
- [Anthropic, "Claude Code hooks"](https://docs.anthropic.com/en/docs/claude-code/hooks) — Deterministic interception before a tool call executes.
- [LangChain middleware](https://docs.langchain.com/oss/python/langchain/middleware) — Framework-level interception points around model and tool calls.

### Cross-references in this suite

- [LLM Role Separation: Executor vs Evaluator](llm-role-separation-executor-evaluator.md) — Seven levels of evaluator isolation and the structural failure modes that isolation alone does not fix.
- [Evaluation-Driven Development](evaluation-driven-development.md) — The measurement infrastructure a gate acts on, and the tier a check must name.
- [Self-Improving Systems](self-improving-systems.md) — Why gate independence bounds how fast a system can improve.
- [Observability and Monitoring](observability-and-monitoring.md) — Logging the three gate outcomes and alerting on drift.

---

*Last reviewed: September 2026. Changed in this revision: the compliance rates on the reliability spectrum are now labelled as the author's operating estimates rather than presented as measurements; added the absent-gate failure mode and its measured wiring-drift finding; added the gate that only checks the shape; added principles on prevention before detection and on proving a gate can refuse; added the 2026 evidence on acting on an accurate critic; corrected the self-preference claim attributed to Panickssery et al.; and added field notes.*
