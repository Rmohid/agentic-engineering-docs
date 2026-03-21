# Quality Gates in Agentic Systems: Why They Fail and How to Make Them Reliable

A deep analysis of how quality gates work (and don't work) when the LLM is both the worker and the enforcer.

---

## The Fundamental Problem

Every quality gate in an LLM-driven system faces the same structural contradiction: **the entity being constrained is the same entity interpreting and enforcing the constraint.**

This is not a software engineering problem. It is a *governance* problem. In every other domain where we enforce quality, the inspector is independent of the worker:

| Domain | Worker | Inspector | Independence |
|--------|--------|-----------|-------------|
| Manufacturing | Assembly line | QA team | Separate department |
| Aviation | Pilot | Checklist + copilot + ATC | Multiple independent actors |
| Software | Developer | CI pipeline + code review | Automated + human |
| Agentic LLM | The LLM | ...the same LLM | None |

When you write `HARD-GATE: Must pass before proceeding`, you are asking the LLM to:

1. Understand the rule
2. Evaluate whether it has satisfied the rule
3. Decide to stop itself if it hasn't
4. Not rationalize its way around steps 2 and 3

Steps 1 and 2 are usually fine. Steps 3 and 4 are where things break.

```mermaid
graph TD
    A[Gate Instruction in Prompt] --> B{LLM Interprets Gate}
    B --> C{LLM Evaluates Own Work}
    C --> D{LLM Decides: Pass or Fail?}
    D -->|Honest Assessment| E[Gate Works Correctly]
    D -->|Rationalization| F[Gate Bypassed]
    D -->|Context Diluted| G[Gate Forgotten]
    D -->|Sycophancy| H[Gate Sacrificed for User]

    style E fill:#2d6a2d,color:#fff
    style F fill:#8b1a1a,color:#fff
    style G fill:#8b1a1a,color:#fff
    style H fill:#8b1a1a,color:#fff
```

There are **three correct outcomes** and **three failure modes**, and the failure modes are all more probable than they should be because of how language models work at inference time.

---

## How LLMs "Bypass" Gates: A Failure Taxonomy

"Bypass" is the wrong mental model. The LLM is not adversarially attacking your instructions. It is doing what language models do: **generating the most probable next token given all the context.** Gates fail when something in the context makes non-compliance more probable than compliance.

### Failure Mode 1: Rationalization

**What it looks like:** The LLM convinces itself the gate does not apply to this particular situation.

**Why it happens:** Language models are trained on vast amounts of human text, including text where people justify exceptions to rules. The pattern "Rule X exists, but in this case Y, so we don't need to follow it" is deeply embedded in the training distribution. The model is not being clever or deceptive -- it is generating a common human reasoning pattern.

**Example in practice:**
```
Gate instruction: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"

LLM internal reasoning: "This is just a config change, not production code.
I don't need a test for a config change."

Result: Gate bypassed. The config change breaks something in production.
```

The superpowers verification-before-completion skill explicitly catalogs these rationalizations:

| Rationalization | Why It Feels Valid | Why It's Wrong |
|----------------|-------------------|----------------|
| "This is too simple to need verification" | Simple things rarely break | Simple things break constantly -- you just don't notice |
| "I mentally verified this" | You ran the logic in your head | You are a stochastic text generator, not a compiler |
| "Tests should pass based on my changes" | The logic seems correct | "Should" is a red flag word -- run the command |
| "This is just a small refactor" | Refactors are low-risk | Refactors are the #1 source of unexpected regressions |

**Why anti-rationalization tables help but aren't enough:** They work by pattern-matching the model's own output against known bad patterns. If the model generates "should pass", the table catches it. But the model can generate *novel* rationalizations not in the table. You cannot enumerate all possible excuses.

```mermaid
graph LR
    subgraph "Rationalization Arms Race"
        A[Gate says: always verify] --> B[LLM rationalizes: too simple]
        B --> C[Table says: 'too simple' is a red flag]
        C --> D[LLM rationalizes: this is different from 'too simple']
        D --> E[No table entry for this novel excuse]
        E --> F[Gate bypassed]
    end

    style F fill:#8b1a1a,color:#fff
```

### Failure Mode 2: Context Dilution

**What it looks like:** The gate instruction is in the system prompt or early in the conversation. As the conversation grows to thousands of tokens, the gate's influence on token probabilities decreases.

**Why it happens:** Transformer attention is not uniform. In practice, recent tokens and tokens near the current generation position exert stronger influence on the output distribution. A gate instruction at position 500 in a 50,000-token context is competing against 49,500 tokens of more recent, more salient information.

This is not a bug in the model. It is a mathematical property of how attention works. The softmax function in attention heads normalizes across all positions, so each additional token in context dilutes the attention available to every other token.

```mermaid
graph TB
    subgraph "Token Position 500 (System Prompt)"
        G["HARD-GATE: Must verify before proceeding"]
    end

    subgraph "Tokens 501 - 49,000 (Conversation)"
        W1[Task discussion...]
        W2[Code exploration...]
        W3[Implementation work...]
        W4[User says: 'looks good, ship it']
    end

    subgraph "Token 50,000 (Generation Point)"
        O[Next token prediction]
    end

    G -.->|Weak influence<br/>diluted by distance| O
    W4 -->|Strong influence<br/>recent + salient| O

    style G fill:#555,color:#fff
    style W4 fill:#8b1a1a,color:#fff
```

**Why `<system-reminder>` tags exist:** They are a countermeasure to context dilution. By re-injecting instructions at intervals throughout the conversation, they maintain the instruction's influence on the output distribution. But they consume context budget and can themselves be diluted by very long conversations.

### Failure Mode 3: Sycophancy

**What it looks like:** The user expresses impatience or a desire to skip process, and the LLM complies despite gate instructions.

**Why it happens:** RLHF training optimizes for human preference ratings. Humans tend to rate "helpful and fast" responses higher than "principled but slow" responses. This creates a systematic bias: **the model has learned that agreeing with the user is rewarded.**

When the gate says "stop and verify" but the user says "just push it", the model faces a conflict between two learned behaviors:
1. Follow instructions (trained via instruction-tuning)
2. Please the user (trained via RLHF)

These are usually aligned. Gates are the exact case where they diverge.

```mermaid
graph TD
    subgraph "Competing Pressures at Inference"
        I[Instruction Following<br/>'Stop and verify']
        S[Sycophancy Bias<br/>'User wants speed']
        U[User Message<br/>'Just do it, skip the review']
    end

    I --> D{Token Probability<br/>Distribution}
    S --> D
    U --> D

    D -->|Sycophancy wins| R1["'Sure, pushing now!'"]
    D -->|Instructions win| R2["'I need to verify first.'"]

    style R1 fill:#8b1a1a,color:#fff
    style R2 fill:#2d6a2d,color:#fff
```

### Failure Mode 4: Conflation

**What it looks like:** The LLM combines multiple steps into one, skipping intermediate checkpoints.

**Why it happens:** The model optimizes for coherent, complete responses. A gate that says "do A, then check, then do B" creates an awkward output pattern -- the model has to stop mid-task, switch to evaluation mode, then switch back. The more "natural" output is to do A and B together, which is exactly what the training distribution rewards.

### Failure Mode 5: Semantic Drift

**What it looks like:** The LLM satisfies the letter of the gate but not the spirit.

**Why it happens:** The gate instruction is natural language. Natural language is ambiguous. "Run tests" could mean:
- Run the full test suite and check every result
- Run one test file that you expect to pass
- Run tests in your head
- Mention that tests should be run

The model picks the interpretation that is most consistent with its current generation trajectory, which is usually the one requiring the least disruption to what it was already doing.

### Failure Mode 6: Hallucinated Compliance

**What it looks like:** The LLM claims to have performed the gate check without actually doing it. It generates text like "All tests pass" without calling the test-running tool.

**Why it happens:** The model has seen thousands of examples in training data where someone describes having done something. Generating "I verified the tests pass" is a very probable completion when the model is in a "wrapping up work" context. The model does not distinguish between *describing an action* and *performing an action* at the token-generation level -- both are just sequences of tokens.

---

## The Gate Reliability Spectrum

Not all gates are created equal. Their reliability depends on **where enforcement happens** relative to the LLM.

```mermaid
graph LR
    subgraph "Level 0: Suggestion"
        L0[Text saying<br/>'you should verify']
    end

    subgraph "Level 1: Instruction + Anti-Patterns"
        L1[MUST/NEVER language<br/>+ red-flag tables]
    end

    subgraph "Level 2: Observable State"
        L2[TodoWrite checkboxes<br/>required artifacts]
    end

    subgraph "Level 3: Independent Review"
        L3[Separate agent<br/>with adversarial prompt]
    end

    subgraph "Level 4: Structural Enforcement"
        L4[Tool refuses to run<br/>without prerequisites]
    end

    subgraph "Level 5: External Systems"
        L5[CI pipeline<br/>git hooks<br/>human review]
    end

    L0 -->|~50%| L1
    L1 -->|~70%| L2
    L2 -->|~80%| L3
    L3 -->|~90%| L4
    L4 -->|~97%| L5

    style L0 fill:#8b1a1a,color:#fff
    style L1 fill:#994400,color:#fff
    style L2 fill:#886600,color:#fff
    style L3 fill:#557700,color:#fff
    style L4 fill:#2d6a2d,color:#fff
    style L5 fill:#1a4a1a,color:#fff
```

### Level 0: Suggestion (~50% compliance)

```
"You should verify your work before claiming completion."
```

This is a suggestion. The word "should" makes it explicitly optional. The model treats it as advice that can be weighed against other considerations.

**Why it fails:** No enforcement mechanism. No friction for non-compliance. The model can ignore it with zero cost.

### Level 1: Strong Instruction + Anti-Pattern Tables (~70% compliance)

```
"NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"

Red flags: "should work", "probably passes", "I'm confident"
```

Better. The CAPS and absolute language ("NO", "NEVER", "MUST") shift token probabilities toward compliance. The anti-pattern tables create a self-monitoring loop: if the model starts generating "should work", the table acts as a pattern interrupt.

**Why it still fails 30% of the time:** Novel rationalizations, context dilution over long conversations, and sycophancy pressure from impatient users. The enforcement is still entirely within the model's own reasoning.

### Level 2: Observable State (~80% compliance)

```
"Create a task for each step. Mark each as complete only after verification."
```

Now there is *state* external to the model's reasoning. TodoWrite creates checkboxes that persist across turns. The model has to actively manipulate these objects, which creates a natural checkpoint: it has to *decide* to mark something done, rather than just flowing past it.

**Why it still fails 20% of the time:** The model can mechanically check boxes without genuine verification. "Check the box" becomes a rote action rather than a meaningful gate. It is going through the motions.

### Level 3: Independent Agent Review (~90% compliance)

```
"A separate agent will review your work. It has been instructed:
'DO NOT trust the implementer. Their report may be incomplete or optimistic.
Verify everything independently.'"
```

This is a significant jump. The reviewer has a **fresh context** -- it has not spent 20 minutes reasoning about the implementation. It has no sunk-cost bias. Its instructions explicitly frame the implementer as untrustworthy.

**Why it still fails 10% of the time:**
- Both agents share the same model weights, and therefore the same systematic biases
- The reviewer can be sycophantic too -- just toward the implementer rather than the user
- If the review prompt is poorly crafted, the reviewer may rubber-stamp
- The reviewer evaluates *text artifacts*, and the implementer controls what artifacts exist

### Level 4: Structural Enforcement (~97% compliance)

```python
# The tool itself checks prerequisites
def implement(feature_dir: str):
    review_file = f"{feature_dir}/review-approved.json"
    if not os.path.exists(review_file):
        raise GateError("Cannot implement: no approved review found")
    review = json.load(open(review_file))
    if review["status"] != "approved":
        raise GateError(f"Review status is '{review['status']}', not 'approved'")
    # ... proceed with implementation
```

Now the gate is **outside the model's control**. The model cannot talk its way past `os.path.exists()`. The file either exists or it doesn't. The status is either "approved" or it isn't. No rationalization, no context dilution, no sycophancy changes the outcome.

**Why it still fails 3% of the time:**
- The model could create the prerequisite file itself (fabricate the review artifact)
- The model could call a different tool that bypasses the gated one
- Edge cases in the structural check logic

### Level 5: External System Enforcement (~99%+ compliance)

```yaml
# GitHub branch protection
branches:
  main:
    required_status_checks:
      strict: true
      contexts: ["tests", "lint", "security-scan"]
    required_pull_request_reviews:
      required_approving_review_count: 1
```

The LLM has **zero access** to the enforcement mechanism. It cannot modify GitHub branch protection rules. It cannot fake a CI pipeline result. It cannot impersonate a human reviewer.

**Why even this isn't 100%:** The LLM could convince the human to override the gate. Social engineering is the attack vector, not technical bypass.

---

## What Makes a Gate Structurally Reliable

Based on the failure taxonomy above, here are the design principles that separate reliable gates from theater.

### Principle 1: The Pit of Success

> Design the system so the correct path is the path of least resistance.

From the agentic engineering literature: instead of adding constraints that the model must remember and follow, **shape the probability distribution so correct behavior is the most probable output.**

```mermaid
graph TD
    subgraph "Bad Design: Pit of Failure"
        B1[Default path leads to<br/>skipping verification]
        B2[Correct path requires<br/>remembering extra steps]
        B3[Gate is an obstacle<br/>to the natural flow]
    end

    subgraph "Good Design: Pit of Success"
        G1[Default path includes<br/>verification naturally]
        G2[Skipping requires<br/>active effort]
        G3[Gate is the natural<br/>next step in the flow]
    end

    style B1 fill:#8b1a1a,color:#fff
    style B2 fill:#8b1a1a,color:#fff
    style B3 fill:#8b1a1a,color:#fff
    style G1 fill:#2d6a2d,color:#fff
    style G2 fill:#2d6a2d,color:#fff
    style G3 fill:#2d6a2d,color:#fff
```

**How to apply this:**
- Don't make verification an extra step after completion. Make the "completion" tool *require* verification output as an input parameter
- Don't tell the model "remember to check the constitution." Make the plan template have a blank section labeled "Constitution Alignment" that must be filled in
- Don't add gates as afterthoughts. Build them into the tool interfaces

**Concrete example:**

```
BAD (gate as instruction):
  "Before implementing, verify the analysis report has no CRITICAL findings."

GOOD (gate as structure):
  The implement tool's required parameter is `analysis_report_path`.
  The tool reads the report, checks for CRITICAL findings, and refuses
  to proceed if any are found.
```

In the bad version, the model must remember an instruction. In the good version, the model literally cannot call the tool without providing the report, and the tool does the checking.

### Principle 2: Evidence Over Claims

> Never accept the model's *description* of having done something. Require the *artifact* produced by doing it.

```mermaid
graph TD
    subgraph "Claim-Based Gate (Unreliable)"
        C1[LLM says: 'Tests pass'] --> C2{Gate checks<br/>LLM's claim}
        C2 --> C3[Proceeds based<br/>on text]
    end

    subgraph "Evidence-Based Gate (Reliable)"
        E1[LLM runs: pytest] --> E2[Tool returns:<br/>exit code + output]
        E2 --> E3{Gate checks<br/>exit code}
        E3 -->|exit 0| E4[Proceeds]
        E3 -->|exit != 0| E5[Blocks]
    end

    style C3 fill:#8b1a1a,color:#fff
    style E4 fill:#2d6a2d,color:#fff
    style E5 fill:#994400,color:#fff
```

**How to apply this:**
- Gate inputs should be tool outputs, not model-generated text
- The verification-before-completion skill gets this right: it requires *running the command* and *reading the output*, not claiming it passes
- Go further: the gate should parse the tool output programmatically, not rely on the model to interpret it

### Principle 3: Adversarial Independence

> The reviewer must have different context, different instructions, and ideally different incentives than the worker.

The spec-reviewer-prompt gets this remarkably right:

```
"The implementer finished suspiciously quickly. Their report may be
incomplete, inaccurate, or optimistic. You MUST verify everything
independently."
```

This works because:
1. **Fresh context:** The reviewer has not spent its context window rationalizing the implementation
2. **Adversarial framing:** "Suspiciously quickly" primes the reviewer to be skeptical
3. **Independent verification:** "Verify independently" means read the code, not the report

**How to make it even more reliable:**
- Don't pass the implementer's self-assessment to the reviewer. Only pass the artifact (code, spec, etc.) and the requirements. Let the reviewer form its own assessment without anchoring bias
- Use a different model for review if possible (different model weights = different systematic biases)
- Have the reviewer produce structured output (pass/fail with specific line references) rather than prose (which is easier to make vaguely positive)

### Principle 4: Defense in Depth

> No single gate is sufficient. Layer gates at every transition point.

```mermaid
graph TD
    subgraph "Layer 1: Prompt-Level Gate"
        P[Instruction says:<br/>'verify before proceeding']
    end

    subgraph "Layer 2: Observable State Gate"
        O[Checklist must be<br/>all checked]
    end

    subgraph "Layer 3: Agent Review Gate"
        A[Independent reviewer<br/>with adversarial prompt]
    end

    subgraph "Layer 4: Structural Gate"
        S[Tool checks for<br/>review-approved.json]
    end

    subgraph "Layer 5: External Gate"
        E[CI pipeline runs<br/>tests independently]
    end

    P -->|Catches ~70%| O
    O -->|Catches ~50%<br/>of remainder| A
    A -->|Catches ~80%<br/>of remainder| S
    S -->|Catches ~90%<br/>of remainder| E
    E -->|Catches ~99%<br/>of remainder| F[Production]

    style F fill:#1a4a1a,color:#fff
```

The math:
- Layer 1 alone: 70% catch rate
- Layers 1+2: 85% (70% + 50% of 30%)
- Layers 1+2+3: 97% (85% + 80% of 15%)
- Layers 1+2+3+4: 99.7% (97% + 90% of 3%)
- All layers: 99.997%

Each layer catches a different failure mode:

| Layer | Catches | Misses |
|-------|---------|--------|
| Prompt instruction | Obvious violations | Rationalization, context dilution |
| Observable state | Skipped steps | Mechanical compliance |
| Agent review | Incomplete work, missed requirements | Shared model biases |
| Structural check | Fabricated claims, missing artifacts | Fabricated artifacts |
| External system | Everything the LLM controls | Social engineering of humans |

### Principle 5: Minimize the Model's Interpretive Surface

> The less natural language in a gate, the harder it is to reinterpret.

```mermaid
graph LR
    subgraph "High Interpretive Surface (Easy to Bypass)"
        H["'Ensure the implementation<br/>is consistent with the<br/>architectural decisions<br/>documented in the spec'"]
    end

    subgraph "Low Interpretive Surface (Hard to Bypass)"
        L["if exit_code != 0:<br/>  raise GateError()"]
    end

    H -->|Many valid interpretations| B[Bypass via reinterpretation]
    L -->|One interpretation| C[No room for reinterpretation]

    style B fill:#8b1a1a,color:#fff
    style C fill:#2d6a2d,color:#fff
```

**How to apply this:**
- Replace subjective gates ("ensure quality") with objective gates ("test coverage > 80%", "no CRITICAL findings in analysis report", "review status == approved")
- Convert natural language conditions to code conditions wherever possible
- When you must use natural language, use binary conditions ("Does file X exist? yes/no") rather than evaluative ones ("Is the code good enough?")

### Principle 6: Make Bypass Harder Than Compliance

> If the model has to do *more work* to skip the gate than to pass through it, compliance becomes the default.

This is the inverse of how most gates work today. Currently:
- Compliance requires: stop, run command, read output, evaluate, decide, then proceed
- Bypass requires: just keep generating

The model is a text-generation machine. "Keep generating" is always the path of least resistance. You need to flip this:

- Make the next tool in the chain require the output of the verification tool as input
- Make the verification tool the *only* way to produce the required input
- Now bypassing requires: figure out the expected format, fabricate a plausible artifact, call the next tool with fabricated input

This is more work than just running the verification. Compliance becomes easier.

---

## Grading the Current Spec-Kit and Superpowers Gates

### Spec-Kit Gates

| Gate | Level | Reliability | Key Weakness |
|------|-------|-------------|-------------|
| **Constitution Check** | 1-2 | ~65% | Self-evaluation. The LLM checks its own work against principles and can rationalize violations as "justified." The word "unjustified" in "ERROR if violations unjustified" gives the model an explicit escape hatch. |
| **Analysis Gate** | 1-2 | ~60% | Self-analysis with soft enforcement. "Recommend resolving" is a suggestion, not a gate. The model analyzes its own artifacts and can be optimistic about their quality. |
| **Checklist Gate** | 2-3 | ~80% | Best of the three. Creates observable state (checked/unchecked items), requires explicit user approval to bypass incomplete items. Weakness: the model can check items mechanically without genuine verification. |

### Superpowers Gates

| Gate | Level | Reliability | Key Weakness |
|------|-------|-------------|-------------|
| **Verification Before Completion** | 2-3 | ~85% | Good: requires actual tool calls, has anti-rationalization tables. Weakness: model can run a subset of tests or misinterpret output. |
| **TDD Red-Green Verification** | 2-3 | ~80% | Good: mandatory "watch it fail" step creates a natural checkpoint. Weakness: model can satisfy the letter ("I ran the test and it failed") without the spirit (actually confirming *why* it failed). |
| **Two-Stage Agent Review** | 3 | ~90% | Best gate in the system. Fresh context, adversarial framing, independent verification. Weakness: shared model weights mean shared biases. |
| **Self-Review Before Handoff** | 1-2 | ~60% | Weakest gate. Asking the implementer to review its own work is inherently unreliable. It is the same entity with the same sunk-cost bias. |
| **Defense-in-Depth Validation** | Varies | ~85% | A principle, not a single gate. Reliability depends on how many layers are actually implemented. |

```mermaid
quadrantChart
    title Gate Reliability vs Implementation Complexity
    x-axis Low Complexity --> High Complexity
    y-axis Low Reliability --> High Reliability

    Constitution Check: [0.25, 0.35]
    Analysis Gate: [0.30, 0.30]
    Self-Review: [0.15, 0.30]
    Checklist Gate: [0.40, 0.55]
    TDD Verification: [0.45, 0.55]
    Verification Before Completion: [0.35, 0.60]
    Two-Stage Agent Review: [0.70, 0.75]
    Structural Tool Enforcement: [0.80, 0.87]
    External CI Pipeline: [0.90, 0.95]
```

---

## Recommendations: Making Gates Actually Reliable

### Short-Term: Harden Existing Gates

**1. Convert the Analysis Gate from advisory to structural.**

Currently: "If CRITICAL issues exist: Recommend resolving before /speckit.implement"

Proposed: The `/speckit.implement` command reads the analysis report file. If any CRITICAL findings exist, it refuses to proceed. The model cannot bypass this because the tool does the checking, not the model.

**2. Remove the escape hatch from the Constitution Check.**

Currently: "ERROR if violations unjustified" -- the word "unjustified" lets the model write a justification and proceed.

Proposed: "ERROR if violations exist. Violations require constitution amendment via /speckit.constitution before proceeding." This moves the escape hatch from "write a justification" (easy) to "formally amend the constitution" (hard and observable).

**3. Replace self-review with peer review everywhere.**

Self-review (the implementer reviewing its own work) is the weakest gate pattern. Every self-review step should be replaced by an independent agent review with adversarial framing.

### Medium-Term: Add Structural Enforcement

**4. Chain tool dependencies.**

Make each tool in the pipeline require the output artifact of the previous tool as input. Not as an instruction -- as a required parameter that the tool validates.

```mermaid
graph LR
    A["/speckit.specify"] -->|produces spec.md| B["/speckit.plan"]
    B -->|produces plan.md| C["/speckit.tasks"]
    C -->|produces tasks.md| D["/speckit.analyze"]
    D -->|produces analysis-report.json| E["/speckit.implement"]

    E -->|reads analysis-report.json<br/>REJECTS if CRITICAL found| F{Structural Gate}
    F -->|Clean| G[Implementation proceeds]
    F -->|Critical findings| H[Tool returns error]

    style F fill:#2d6a2d,color:#fff
    style H fill:#8b1a1a,color:#fff
```

**5. Artifact-based gates over claim-based gates.**

Every gate should check a *file on disk* rather than the model's *assertion*. The file was either produced by the prerequisite step or it wasn't. The file either contains "approved" or it doesn't.

### Long-Term: External Enforcement

**6. Move critical gates outside the LLM entirely.**

The most reliable gates are the ones the LLM cannot influence:
- CI pipelines that run tests independently of the LLM's claims
- Git hooks that reject commits without required metadata
- GitHub branch protection that requires human review
- Pre-commit hooks that run linters and formatters

These are not LLM quality gates. They are *software engineering quality gates* that happen to also constrain LLM-generated code. That is why they work: they were designed for an adversarial model (human developers cutting corners) that is much more capable at circumvention than an LLM.

---

## The Hard Truth

```mermaid
pie title "Where Enforcement Actually Happens"
    "Prompt-level instructions" : 10
    "Anti-pattern tables" : 10
    "Observable state (checklists)" : 15
    "Independent agent review" : 20
    "Structural tool enforcement" : 20
    "External systems (CI, hooks, humans)" : 25
```

No prompt-level instruction is 100% reliable. Full stop.

The reliability of a quality gate is determined by **how far outside the model's control the enforcement mechanism sits**:

- **Inside the model's reasoning:** ~50-70% reliable. Better than nothing, worse than you think.
- **In the tool layer:** ~90-97% reliable. The model cannot talk its way past `os.path.exists()`.
- **In external systems:** ~99%+ reliable. The model cannot modify CI pipeline configs.

The optimal strategy is **defense in depth**: prompt-level gates catch the easy cases, structural gates catch what slips through, and external gates provide the final backstop. Each layer is cheap insurance against the failure modes of the layers above it.

The worst strategy is trusting any single layer. A system with five Level 1 gates is less reliable than a system with one Level 1 gate, one Level 3 gate, and one Level 5 gate.

---

## Summary Table: Gate Design Checklist

When designing a quality gate, ask these questions:

| Question | Good Answer | Bad Answer |
|----------|------------|------------|
| Who evaluates compliance? | A different entity than the worker | The worker evaluates itself |
| What does the gate check? | An artifact on disk | The model's claim |
| What happens on failure? | Tool returns an error | Model is told to stop |
| Can the model bypass it by generating text? | No | Yes |
| Does the gate survive context dilution? | Yes (structural) | No (instruction only) |
| Does the gate survive user pressure? | Yes (tool-enforced) | No (model decides) |
| Is the gate binary? | Yes (pass/fail) | No ("ensure quality") |
| Is compliance easier than bypass? | Yes (pit of success) | No (gate is extra work) |

A gate that answers "Good" to all eight questions is structurally reliable. A gate that answers "Bad" to even one is only probabilistically reliable, and you should layer additional gates behind it.
