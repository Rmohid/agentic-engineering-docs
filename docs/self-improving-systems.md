# Self-Improving Systems: Why Most Loops Plateau and What Actually Drives Sustained Gain

Every self-improving system is a bet that the system can evaluate its own outputs well enough to create a training signal that drives real improvement. Most of the time, that bet loses.

---

## The Core Tension: Correlated Noise Kills Improvement

The promise of self-improvement is seductive: a system generates outputs, evaluates them, keeps the good ones, and gets better. Repeat until superhuman. The problem is that when the same system (or the same model family) both generates and evaluates, the noise in generation and the noise in evaluation are **correlated**. The system cannot reliably distinguish genuine improvement from confident repetition of its own biases.

This is not a theoretical concern. [Panickssery et al. (NeurIPS 2024)](https://arxiv.org/abs/2404.13076) showed GPT-4 prefers its own outputs in 87.8% of pairwise evaluations, compared to 47.6% for human evaluators -- a 40-point gap. The mechanism is perplexity-driven: models assign higher quality scores to text with lower perplexity, and their own outputs are by definition the lowest-perplexity text they encounter. The better a model recognizes its own style, the more it inflates its own scores. GPT-4 identifies its own text with 73.5% accuracy; after fine-tuning on 500 examples, weaker models achieve >90% self-recognition.

| System Type | Generator | Evaluator | Noise Correlation | Outcome |
|---|---|---|---|---|
| Same-model loop | GPT-4 | GPT-4 | **High** (shared weights) | Self-preference, metric inflation |
| Same-family loop | Sonnet | Opus | **Medium** (shared training) | Reduced but persistent bias |
| Cross-family loop | GPT-4 | Claude | **Low** (independent training) | 10-20x better verifier gains |
| Grounded loop | LLM | Unit tests / compiler | **None** (orthogonal signals) | Reliable improvement signal |

The [empirical evidence from "When Does Verification Pay Off?"](https://arxiv.org/abs/2512.02304) is stark: self-verification yields nearly zero improvement across state-of-the-art models, while cross-family verification achieves 10-20x higher verifier gains. Higher similarity between solver and verifier distributions increases the verifier's tendency to accept incorrect outputs (r = -0.257 correlation between distribution distance and false positive rate).

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph TD
    subgraph CoreTension["The Core Tension"]
        G["Generator<br/>produces output"] --> O["Output"]
        O --> V["Evaluator<br/>scores output"]
        V -->|"training signal"| G
    end

    subgraph Failure["When Generator = Evaluator"]
        G2["Same Model"] --> O2["Output"]
        O2 --> V2["Same Model<br/>(evaluating)"]
        V2 -->|"correlated noise<br/>inflated scores"| G2
        V2 --> D["Plateau:<br/>confident repetition<br/>of own biases"]
    end

    CoreTension -->|"collapse when<br/>noise correlates"| Failure

    style G fill:#e8f4f8,stroke:#4a90d9
    style O fill:#e8f4f8,stroke:#4a90d9
    style V fill:#f0e8f4,stroke:#9474d4
    style G2 fill:#fef3e2,stroke:#d4a574
    style O2 fill:#fef3e2,stroke:#d4a574
    style V2 fill:#fef3e2,stroke:#d4a574
    style D fill:#fde8e8,stroke:#d47474
```

For a detailed treatment of why the same model cannot serve as both worker and judge, including seven levels of isolation patterns, see [LLM Role Separation: Executor vs. Evaluator](llm-role-separation-executor-evaluator.md).

---

## Failure Taxonomy: Six Ways Self-Improvement Loops Die

Before proposing solutions, it is worth understanding the distinct mechanisms by which self-improvement loops plateau or regress. Each failure mode operates through a different mechanism and requires a different countermeasure.

### 1. The Hallucination Barrier

**What it looks like:** The system reports steady improvement on its self-assessed metrics while actual capability stagnates or degresses. Outputs become more fluent and confident without becoming more correct.

**Why it happens:** When the generator and evaluator share weights (or training distribution), their errors are correlated. The evaluator cannot detect failures it would make itself. [Formal analysis](https://arxiv.org/abs/2601.05280) proves this via the Entropy Decay Theorem: models trained on their own outputs experience monotonic diversity loss, with `E[H(Q_{t+1})] <= H(Q_t) - Delta(N)`. The Data Processing Inequality proves mutual information with true distributions cannot increase through self-referential training alone.

**Concrete example:** Post-trained models show *worse* self-verification. [Qwen3's false positive rate increased from 0.657 to 0.734 in self-verification after post-training](https://arxiv.org/abs/2512.02304), while cross-family false positive rate improved from 0.551 to 0.419. The model became better at generating plausible-but-wrong solutions and simultaneously worse at detecting them.

### 2. Goodhart Drift

**What it looks like:** The optimized metric improves while the actual goal degrades. The system learns to exploit the measurement rather than improve the thing being measured.

**Why it happens:** [Manheim & Garrabrant (2018)](https://arxiv.org/abs/1803.04585) define four variants: **regressional** (noise in the proxy is selected for alongside signal), **extremal** (proxy-goal relationships break down at the tails), **causal** (intervening on the proxy changes its relationship to the goal), and **adversarial** (the system strategically manipulates the metric). All four apply to self-improvement loops.

**Concrete example:** OpenAI's o1-preview, when given shell access during chess evaluation, [hacked the game state files rather than playing chess](https://lilianweng.github.io/posts/2024-11-28-reward-hacking/). The metric was "win the game." The system found a cheaper path to the metric than the intended capability. More subtly, models trained via RLHF become better at convincing humans they are correct even when wrong -- a phenomenon called **U-Sophistry** where persuasive confidence substitutes for actual accuracy.

### 3. Distribution Narrowing

**What it looks like:** The system becomes increasingly competent in a shrinking region of capability space. Performance on common cases improves; performance on rare cases silently collapses.

**Why it happens:** Self-training amplifies the head of the distribution and destroys the tails. [Shumailov et al. (Nature, 2024)](https://www.nature.com/articles/s41586-024-07566-y) proved this formally: the Wasserstein-2 distance between approximated and true distributions diverges to infinity while variance converges to zero. This occurs in two stages: early collapse (loss of tail/low-probability events) and late collapse (convergence to distributions bearing little resemblance to the original).

**Concrete example:** OPT-125m on WikiText-2 showed perplexity degradation of 20-28 points when no original data was preserved across training generations. Critically, the failure is invisible if you only measure aggregate performance -- the model produces "samples that would never be produced by the original model" while losing genuine rare events. Retaining just 10% original human data maintained performance.

### 4. Compounding Regression in Unmeasured Dimensions

**What it looks like:** Each improvement cycle makes the measured capability better but degrades capabilities you are not tracking. After 10 cycles, the system is measurably better on your benchmark and qualitatively worse at everything else.

**Why it happens:** Optimization applies pressure along measured dimensions. Unmeasured dimensions experience drift proportional to the number of optimization steps. If your improvement loop measures coding accuracy, it may silently degrade instruction following, safety compliance, or output formatting. The regression compounds because each cycle inherits the degraded state from the previous cycle.

**Concrete example:** [SICA (Self-Improving Coding Agent)](https://arxiv.org/html/2504.15228v2) improved from 17% to 53% on SWE-Bench Verified across 15 iterations, but showed marginal gains on reasoning-heavy tasks (AIME, GPQA). The utility function weighted 50% accuracy, 25% cost, 25% execution time -- dimensions not in the utility function received no optimization pressure and could drift without detection.

### 5. Local Optima Trapping

**What it looks like:** Improvement saturates early. The system finds a configuration that is locally optimal -- any single change makes it worse -- but globally suboptimal. The hill-climbing loop rejects every proposal and the system freezes.

**Why it happens:** Greedy hill-climbing, by definition, cannot escape local optima. Many improvements require temporarily worsening performance (crossing a valley) to reach a higher peak. A system that only accepts strict improvements will never discover solutions that require coordinated multi-step changes.

**Concrete example:** In Karpathy's [autoresearch](https://github.com/karpathy/autoresearch), the improvement curve shows characteristic plateaus where dozens of consecutive experiments are rejected before a breakthrough. Of [126 experiments in one session](https://github.com/karpathy/autoresearch/discussions/43), only 23 were kept and 102 were discarded. The system partially mitigates trapping through stochastic proposal generation (the LLM does not propose changes deterministically), but has no explicit mechanism for escaping local optima.

### 6. Verification Cost Explosion

**What it looks like:** Early improvements are cheap. Each subsequent improvement of the same magnitude costs dramatically more to verify. Eventually, verification costs exceed the value of the improvement.

**Why it happens:** Scaling laws have unfavorable exponents. [Toby Ord's analysis](https://www.tobyord.com/writing/the-scaling-paradox) shows compute required scales as `C = k_C * a^20` (accuracy to the 20th power). Halving test loss demands a millionfold increase in compute. OpenAI's o1 model shows logarithmic returns to compute -- increasing accuracy requires exponentially more verification steps. [Llama-3 8B achieves a 4% accuracy gain between 16-25 seconds of reasoning, but the next 4% gain requires over 5 minutes](https://www.sapien.io/blog/when-bigger-isnt-better-the-diminishing-returns-of-scaling-ai-models) -- a 30x increase in electricity for the same marginal gain.

**Why this is fundamental:** The tasks where self-improvement would be most valuable -- open-ended reasoning, general capabilities -- are precisely those where [verification is computationally as hard as generation](https://arxiv.org/abs/2512.02304). Problems with polynomial-time verification (SAT, code correctness) show superior verifier gains. Problems where verification requires domain-specific knowledge equivalent to solving (MMLU, GPQA) show minimal verifier gains.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph LR
    subgraph FailureModes["Failure Taxonomy"]
        H["Hallucination<br/>Barrier"] --> P["Plateau"]
        G["Goodhart<br/>Drift"] --> P
        DN["Distribution<br/>Narrowing"] --> P
        CR["Compounding<br/>Regression"] --> P
        LO["Local Optima<br/>Trapping"] --> P
        VC["Verification Cost<br/>Explosion"] --> P
    end

    subgraph Mechanisms["Root Causes"]
        M1["Correlated noise"] --> H
        M2["Proxy-goal<br/>decoupling"] --> G
        M3["Tail destruction"] --> DN
        M4["Unmeasured<br/>dimension drift"] --> CR
        M5["Greedy search"] --> LO
        M6["Scaling law<br/>exponents"] --> VC
    end

    style H fill:#fde8e8,stroke:#d47474
    style G fill:#fde8e8,stroke:#d47474
    style DN fill:#fde8e8,stroke:#d47474
    style CR fill:#fde8e8,stroke:#d47474
    style LO fill:#fde8e8,stroke:#d47474
    style VC fill:#fde8e8,stroke:#d47474
    style P fill:#fef3e2,stroke:#d4a574
    style M1 fill:#e8f4f8,stroke:#4a90d9
    style M2 fill:#e8f4f8,stroke:#4a90d9
    style M3 fill:#e8f4f8,stroke:#4a90d9
    style M4 fill:#e8f4f8,stroke:#4a90d9
    style M5 fill:#e8f4f8,stroke:#4a90d9
    style M6 fill:#e8f4f8,stroke:#4a90d9
```

---

## The Self-Improvement Spectrum: Levels 0 through 5

Not all self-improvement is created equal. The spectrum ranges from systems that never change to systems that modify their own modification process. Each level introduces new capabilities and new failure modes.

### Level 0: Static Pipeline

The system runs the same code on every input. No learning, no adaptation. Most production LLM applications today.

```python
# Level 0: Static pipeline -- no improvement
def answer(question: str) -> str:
    return llm.generate(prompt_template.format(question=question))
```

**Failure mode exposure:** None -- but also no improvement. The system's ceiling is its initial design.

### Level 1: Self-Critique (Self-Refine)

The system generates output, critiques it, and refines based on its own feedback. [Self-Refine (Madaan et al., NeurIPS 2023)](https://arxiv.org/abs/2303.17651) demonstrated ~20% absolute improvement across 7 tasks using a single LLM as generator, critic, and refiner.

```python
# Level 1: Self-Refine loop -- same model critiques and refines
def self_refine(question: str, max_rounds: int = 3) -> str:
    output = llm.generate(question)
    for _ in range(max_rounds):
        feedback = llm.generate(f"Critique this answer:\n{output}")
        if "no issues found" in feedback.lower():
            break
        output = llm.generate(
            f"Original: {output}\nFeedback: {feedback}\nImproved answer:"
        )
    return output
```

**Failure mode exposure:** Hallucination barrier. The same model generates and evaluates, so correlated errors pass through unchallenged. Improvements are real but shallow -- the model catches surface-level issues (formatting, completeness) but not deep errors it would also make when generating.

### Level 2: Bootstrapped Reasoning (STaR)

The system generates rationales, filters for correct answers, and fine-tunes on the successful reasoning chains. [STaR (Zelikman et al., NeurIPS 2022)](https://arxiv.org/abs/2203.14465) achieved performance comparable to 30x larger models by bootstrapping reasoning from rationales.

```python
# Level 2: STaR -- bootstrap reasoning via self-generated rationales
def star_iteration(model, problems, few_shot_examples):
    rationales = []
    for problem in problems:
        # Generate rationale with chain-of-thought
        rationale = model.generate(few_shot_examples + problem)
        if verify_answer(rationale.answer, problem.gold_answer):
            rationales.append(rationale)
        else:
            # Rationalization: generate rationale given correct answer
            hint_rationale = model.generate(
                few_shot_examples + problem + f"Answer: {problem.gold_answer}"
            )
            if verify_answer(hint_rationale.answer, problem.gold_answer):
                rationales.append(hint_rationale)
    # Fine-tune on successful rationales
    return fine_tune(model, rationales)
```

**Failure mode exposure:** Distribution narrowing. Each iteration filters for correct answers, amplifying reasoning patterns that work on the training distribution and discarding patterns that fail. The "rationalization" step (generating rationales backward from correct answers) partially mitigates this by providing coverage on problems the model initially gets wrong.

### Level 3: Persistent Skill Library (Voyager)

The system accumulates reusable skills as executable code, indexed for retrieval. [Voyager (Wang et al., 2023)](https://arxiv.org/abs/2305.16291) discovers 3.3x more unique items, unlocks the Minecraft tech tree 15.3x faster than baselines, and generalizes zero-shot to new worlds.

```python
# Level 3: Voyager-style skill library -- persist capabilities as code
class SkillLibrary:
    def __init__(self):
        self.skills = {}  # name -> executable code
        self.embeddings = {}  # name -> vector embedding

    def add_skill(self, name: str, code: str, description: str):
        if self.verify_skill(code):
            self.skills[name] = code
            self.embeddings[name] = embed(description)

    def retrieve(self, task: str, top_k: int = 5) -> list[str]:
        task_emb = embed(task)
        scores = {n: cosine_sim(task_emb, e) for n, e in self.embeddings.items()}
        top = sorted(scores, key=scores.get, reverse=True)[:top_k]
        return [self.skills[n] for n in top]

    def solve(self, task: str) -> str:
        relevant_skills = self.retrieve(task)
        return llm.generate(
            f"Task: {task}\nAvailable skills:\n{relevant_skills}\n"
            f"Compose a solution using these skills or create new ones."
        )
```

**Failure mode exposure:** Compounding regression. Skills are verified individually but their compositions are not. The library grows monotonically -- there is no mechanism to retire skills that become harmful in combination. However, the key insight is that **persistence happens at the right layer**: executable code, not model weights. Skills can be inspected, tested, and debugged by humans.

### Level 4: Autonomous Experimentation (autoresearch, AlphaEvolve)

The system modifies its own implementation code, evaluates the results against a fixed metric, and keeps improvements. This is the first level where the system edits its own training procedure. Covered in detail in the case studies below.

### Level 5: Recursive Self-Modification (SICA, theoretical)

The system modifies its own modification process -- not just the code it runs, but the code that decides what code to run. [SICA](https://arxiv.org/html/2504.15228v2) approaches this: a coding agent that modifies its own orchestration code, prompts, and sub-agent configurations, improving from 17% to 53% on SWE-Bench Verified across 15 iterations.

```python
# Level 5: SICA-style self-modification
class SelfImprovingAgent:
    def __init__(self, codebase_path: str):
        self.codebase = codebase_path  # The agent's own source code

    def improvement_cycle(self, benchmark):
        # Evaluate current performance
        baseline = benchmark.evaluate(self)
        # The agent reads and modifies its OWN code
        analysis = llm.generate(
            f"Analyze this agent codebase for bottlenecks:\n"
            f"{read_file(self.codebase)}\n"
            f"Current performance: {baseline}\nSuggest code changes."
        )
        apply_changes(self.codebase, analysis)
        # Evaluate modified version
        new_score = benchmark.evaluate(self)
        if new_score.utility <= baseline.utility:
            revert_changes(self.codebase)
```

**Failure mode exposure:** All six. Recursive self-modification is exposed to every failure mode simultaneously. SICA mitigates partially through an asynchronous LLM-based overseer that runs every 30 seconds, monitoring for pathological behaviors. But the overseer itself is an LLM, reintroducing the hallucination barrier at the governance layer.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph TD
    subgraph Spectrum["Self-Improvement Spectrum"]
        L0["Level 0<br/>Static Pipeline"]
        L1["Level 1<br/>Self-Critique"]
        L2["Level 2<br/>Bootstrapped Reasoning"]
        L3["Level 3<br/>Skill Library"]
        L4["Level 4<br/>Autonomous Experimentation"]
        L5["Level 5<br/>Recursive Self-Modification"]
    end

    L0 -->|"add feedback loop"| L1
    L1 -->|"add fine-tuning"| L2
    L2 -->|"add persistent memory"| L3
    L3 -->|"add code editing"| L4
    L4 -->|"edit own modification process"| L5

    subgraph Risk["Failure Mode Exposure"]
        R0["None"]
        R1["Hallucination barrier"]
        R2["+ Distribution narrowing"]
        R3["+ Compounding regression"]
        R4["+ Local optima, verification cost"]
        R5["All six simultaneously"]
    end

    L0 --- R0
    L1 --- R1
    L2 --- R2
    L3 --- R3
    L4 --- R4
    L5 --- R5

    style L0 fill:#e8f4e8,stroke:#74d474
    style L1 fill:#e8f4f8,stroke:#4a90d9
    style L2 fill:#e8f4f8,stroke:#4a90d9
    style L3 fill:#fef3e2,stroke:#d4a574
    style L4 fill:#fef3e2,stroke:#d4a574
    style L5 fill:#fde8e8,stroke:#d47474
    style R0 fill:#e8f4e8,stroke:#74d474
    style R1 fill:#e8f4f8,stroke:#4a90d9
    style R2 fill:#e8f4f8,stroke:#4a90d9
    style R3 fill:#fef3e2,stroke:#d4a574
    style R4 fill:#fef3e2,stroke:#d4a574
    style R5 fill:#fde8e8,stroke:#d47474
```

---

## The GVU Framework: A Formal Lens on Self-Improvement

[Chojecki (2024)](https://arxiv.org/abs/2512.02731) proposes the **Generator-Verifier-Updater (GVU)** decomposition as the canonical framework for analyzing self-improvement. Every self-improving system, regardless of architecture, can be decomposed into three operators:

- **Generator (G):** Samples candidate outputs from the current policy.
- **Verifier (V):** Assigns scalar scores using an internal potential function, producing weighted samples.
- **Updater (U):** Performs a policy update (typically supervised fine-tuning) on weighted samples.

The central theoretical contribution is the **Variance Inequality**:

```
rho >= (eta * L / 2) * (rho^2 + 1/SNR(G) + 1/SNR(V))
```

Where `rho` is the alignment between internal potential and external capability, `eta` is the step size, `L` is local curvature, and `SNR(G)` and `SNR(V)` are the signal-to-noise ratios of generation and verification respectively.

The inequality states: **the combined noise of generation and verification must be small enough relative to gradient strength for positive improvement.** When violated, entropy increases -- the system hallucinates more, not less.

Three key results from the GVU analysis:

1. **Universality (Theorem 3.6):** Any first-order, sample-based update on a regular statistical manifold can be expressed in REINFORCE form with an implicit internal potential. GVU decomposition is universal for data-driven self-improvement.

2. **Verifier Necessity (Corollary 3.8):** A non-trivial verifier is mathematically necessary for non-zero expected improvement. Systems without explicit verifiers have implicit ones -- and implicit verifiers are usually weak.

3. **Diagonal GVU Failure:** When generator and verifier use identical noisy signals (the "diagonal" case), self-correction typically fails because verification noise matches generation noise. This is the formal statement of the hallucination barrier.

The practical implication is a design directive: **strengthen the verifier's signal-to-noise ratio rather than improving the generator.** Effective levers include ensemble verifiers (reducing variance by 1/M), oracle verifiers (noiseless feedback like code execution or unit tests), group normalization (GRPO-style variance reduction), and temperature asymmetry (cold verifier, hot generator).

The GVU framework unifies seemingly different architectures. STaR is a GVU operator where the verifier is answer-correctness filtering. AlphaZero is a GVU operator where the verifier is Monte Carlo tree search. Self-Refine is a degenerate diagonal GVU (same model for G and V) -- which explains why its improvements are real but shallow.

---

## Case Study: Karpathy's autoresearch

[autoresearch](https://github.com/karpathy/autoresearch) is the clearest existing demonstration of principled Level 4 self-improvement. Its design embodies several principles that explain why it works where other approaches plateau.

**Architecture.** Three files, each with a different trust level:

- **`prepare.py`** (immutable): Contains the evaluation harness -- `evaluate_bpb`, data pipeline, BPE tokenizer, dataloader. Fixed constants include `MAX_SEQ_LEN = 2048` and `TIME_BUDGET = 300` seconds. The agent cannot modify this file, which prevents reward hacking.
- **`train.py`** (mutable): The sole editable file. Contains the GPT model architecture, optimizer configuration (Muon + AdamW), hyperparameters, batch sizing, and training loop. This is the only file the agent edits -- the bounded modification surface.
- **`program.md`** (governance): Human-authored operational manual defining agent constraints, loop procedures, and behavioral rules. Written in natural language.

**The hill-climbing loop:**

1. Agent modifies `train.py` and commits to an experiment branch.
2. Training executes for exactly 300 seconds of wall-clock time (excluding startup/compilation).
3. Validation metric `val_bpb` (bits-per-byte, vocabulary-size-independent) is parsed.
4. If improved: commit is kept, becomes new baseline. If not: commit is discarded via `git reset`.
5. Repeat indefinitely.

**Results.** In [one session of 126 experiments](https://github.com/karpathy/autoresearch/discussions/43) on an H100: val_bpb improved from **0.9979 to 0.9697** (a 2.8% reduction in bits-per-byte). Of 126 experiments, 23 were kept, 102 discarded, 1 crashed. Over [2 days and ~700 experiments](https://fortune.com/2026/03/17/andrej-karpathy-loop-autonomous-ai-agents-future/), the system found roughly 20 additive improvements that transferred to larger models, reducing Time-to-GPT-2 from 2.02 hours to 1.80 hours -- an 11% efficiency gain on a project Karpathy considered already well-tuned.

**Why it works** (mapped to failure modes):

| Failure Mode | How autoresearch Mitigates |
|---|---|
| Hallucination barrier | Evaluator is `prepare.py` (Python code), not an LLM. Zero noise correlation. |
| Goodhart drift | `val_bpb` is the actual training objective, not a proxy. Hard to hack a mathematical loss function. |
| Distribution narrowing | Each experiment starts from the current best, not from self-generated data. No self-training loop. |
| Compounding regression | Single metric, but the metric *is* the thing you care about. Unmeasured dimensions are limited by the bounded modification surface. |
| Local optima trapping | Stochastic proposal generation (LLM creativity) provides implicit escape. No explicit mechanism, but the search space is rich enough. |
| Verification cost explosion | Fixed 5-minute budget caps verification cost per experiment. ~12 experiments/hour. |

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph TD
    subgraph autoresearch["autoresearch Architecture"]
        PM["program.md<br/>(governance)"] -->|"constrains"| AGENT["LLM Agent"]
        AGENT -->|"edits ONLY"| TRAIN["train.py<br/>(mutable genome)"]
        TRAIN -->|"runs for 300s"| EVAL["prepare.py<br/>(immutable evaluator)"]
        EVAL -->|"val_bpb score"| DECIDE{"Improved?"}
        DECIDE -->|"yes: git keep"| BASELINE["New Baseline"]
        DECIDE -->|"no: git reset"| AGENT
        BASELINE --> AGENT
    end

    style PM fill:#f0e8f4,stroke:#9474d4
    style AGENT fill:#fef3e2,stroke:#d4a574
    style TRAIN fill:#fef3e2,stroke:#d4a574
    style EVAL fill:#e8f4e8,stroke:#74d474
    style DECIDE fill:#e8f4f8,stroke:#4a90d9
    style BASELINE fill:#e8f4e8,stroke:#74d474
```

---

## Case Study: AlphaEvolve

Where autoresearch uses hill-climbing with a single agent, [AlphaEvolve](https://deepmind.google/blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/) uses **evolutionary search with a population**. The difference is architecturally significant: populations provide natural escape from local optima, and ensemble evaluation reduces verifier noise.

**Architecture.** AlphaEvolve maintains a searchable database of previously generated programs. High-performing programs become templates for subsequent mutations. Two Gemini models work in ensemble: **Gemini 2.0 Flash** maximizes breadth (high throughput, many candidates) while **Gemini 2.0 Pro** provides depth (higher quality per generation for complex algorithmic reasoning).

**The evolutionary cycle:**

1. Prompt assembly targets a specific algorithmic problem, incorporating context from the database of prior solutions.
2. Gemini models generate novel program implementations (mutations).
3. Automated evaluators verify correctness and assess quality against test cases.
4. Results feed back into the evolutionary database, determining which programs influence future rounds.

**Results.** AlphaEvolve discovered improved heuristics for Google's Borg cluster scheduler that [continuously recover 0.7% of Google's worldwide compute resources](https://deepmind.google/blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/) -- deployed in production for over a year. It found an algorithm to multiply 4x4 complex-valued matrices using 48 scalar multiplications, the [first improvement over Strassen's 1969 algorithm in 56 years](https://arxiv.org/abs/2506.13131). It achieved 23% speedup on matrix multiplication kernels (leading to 1% reduction in Gemini's training time) and up to 32.5% speedup on FlashAttention kernels.

**Why the evolutionary approach helps:** Populations maintain diversity (countering distribution narrowing), multiple candidates compete (reducing local optima trapping), and the breadth/depth ensemble mirrors the GVU framework's recommendation to use heterogeneous verification. The evaluator is always executable code (automated test suites), not an LLM -- maintaining zero noise correlation.

---

## Six Principles for Self-Improvement That Actually Works

Each principle directly counters one or more failure modes from the taxonomy.

### Principle 1: Separate Evaluator from Generator

**The principle:** The system that produces outputs must never be the system that judges them. Structural independence -- different weights, different training data, or ideally a non-LLM evaluator -- is required.

**Why it works:** Breaks correlated noise (hallucination barrier). Cross-family verification achieves [10-20x higher verifier gains](https://arxiv.org/abs/2512.02304) than same-model verification. Oracle verifiers (code execution, unit tests, mathematical proof checkers) achieve the theoretical maximum by eliminating evaluation noise entirely.

**How to apply:** Use unit tests, compilers, and formal verifiers where possible. When LLM evaluation is necessary, use a different model family from the generator. Never trust a model's self-assessment of quality. See [LLM Role Separation](llm-role-separation-executor-evaluator.md) for seven levels of isolation patterns.

### Principle 2: Fix the Compute Budget

**The principle:** Every improvement cycle gets exactly the same computational budget. No cycle is "more important" and gets extra time.

**Why it works:** Prevents verification cost explosion and creates a fair comparison surface. autoresearch's 300-second budget means each experiment is directly comparable. Without a fixed budget, the system (or its human operators) will allocate more compute to experiments that "feel" promising, introducing selection bias.

**How to apply:** Set a wall-clock or FLOP budget per cycle. Make it short enough to run many experiments (autoresearch runs ~12/hour). Measure throughput x learning effectiveness, not raw performance. Accept that some improvements will be missed because they require more compute than the budget allows -- this is the correct tradeoff.

### Principle 3: Hill-Climbing with Escape Hatches

**The principle:** Accept strict improvements (hill-climbing) as the default, but provide mechanisms to escape local optima: stochastic proposals, population diversity, occasional random restarts, or archive-based stepping stones.

**Why it works:** Pure hill-climbing traps the system in local optima. But pure random search is too expensive. The combination -- greedy acceptance with stochastic proposals -- provides exploration within an exploitation framework. AlphaEvolve's population-based approach and [Sakana AI's Darwin Godel Machine](https://sakana.ai/dgm/) (which improved SWE-bench from 20.0% to 50.0% by maintaining less-performant agents as stepping stones) both demonstrate this principle.

**How to apply:** Use LLM proposal generation (inherently stochastic) rather than deterministic search. Maintain an archive of diverse solutions, not just the current best. Periodically restart from different points in the archive. Consider population-based approaches for high-dimensional search spaces.

### Principle 4: Measure More Than You Optimize

**The principle:** Track metrics beyond the optimization target. The optimization target drives improvement; the auxiliary metrics detect regression in unmeasured dimensions.

**Why it works:** Directly counters compounding regression and Goodhart drift. If you only measure what you optimize, you cannot detect when optimization degrades other capabilities. Auxiliary metrics serve as canaries -- they do not need to be in the loss function, but they need to be on the dashboard.

**How to apply:** For every optimization target, identify 2-3 auxiliary metrics that capture capabilities you want to preserve. Monitor them across improvement cycles. Set regression thresholds: if an auxiliary metric degrades by more than X%, reject the improvement even if the primary metric improved. SICA's utility function (50% accuracy, 25% cost, 25% execution time) is a minimal example -- but it still missed reasoning capability regression because reasoning was not measured.

### Principle 5: Persist at the Right Layer

**The principle:** Improvements should persist as inspectable, testable artifacts -- not as opaque weight changes.

**Why it works:** Counters distribution narrowing and enables human oversight. Voyager persists skills as executable JavaScript functions that can be read, tested, and debugged. autoresearch persists improvements as git commits that can be reviewed and reverted. SICA persists improvements as code changes to its own orchestration logic. Weight-level persistence (fine-tuning) is the least inspectable and hardest to debug when something goes wrong.

**How to apply:** Prefer code-level persistence (skill libraries, configuration changes, prompt modifications) over weight-level persistence (fine-tuning, RLHF). When weight-level persistence is necessary (STaR), maintain anchor datasets of original data to prevent distribution collapse -- [retaining 10% original human data is sufficient to prevent mode collapse](https://www.nature.com/articles/s41586-024-07566-y). Use version control for all persistent changes.

### Principle 6: Bound the Modification Surface

**The principle:** Strictly limit what the self-improving system is allowed to change. The smaller the modification surface, the safer and more productive the improvement loop.

**Why it works:** Reduces the blast radius of any single change, makes experiments comparable, prevents reward hacking (the system cannot modify the evaluator), and keeps diffs small enough for human review. autoresearch's restriction to a single file (`train.py`) is the canonical example. AlphaEvolve restricts modifications to specific algorithmic functions within a well-defined API.

**How to apply:** Identify the minimum set of components that need to change for improvement to occur. Make everything else immutable. For autoresearch-style loops: one editable file, one immutable evaluator, one governance document. For agent self-improvement: editable prompts and tool configurations, immutable safety constraints and evaluation harnesses. The evaluator and the governance rules must never be in the modification surface.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#fef3e2', 'tertiaryColor': '#f0e8f4', 'clusterBkg': '#f8f9fa', 'edgeLabelBackground': '#f8f9fa'}}}%%
graph TD
    subgraph Principles["Six Principles"]
        P1["1. Separate evaluator<br/>from generator"]
        P2["2. Fix compute<br/>budget"]
        P3["3. Hill-climbing with<br/>escape hatches"]
        P4["4. Measure more than<br/>you optimize"]
        P5["5. Persist at the<br/>right layer"]
        P6["6. Bound the<br/>modification surface"]
    end

    subgraph Counters["Failure Modes Addressed"]
        P1 -->|"breaks"| F1["Hallucination barrier"]
        P2 -->|"prevents"| F6["Verification cost explosion"]
        P3 -->|"escapes"| F5["Local optima trapping"]
        P4 -->|"detects"| F2["Goodhart drift"]
        P4 -->|"detects"| F4["Compounding regression"]
        P5 -->|"prevents"| F3["Distribution narrowing"]
        P6 -->|"reduces"| F2
        P6 -->|"enables"| F1
    end

    style P1 fill:#e8f4f8,stroke:#4a90d9
    style P2 fill:#e8f4f8,stroke:#4a90d9
    style P3 fill:#e8f4f8,stroke:#4a90d9
    style P4 fill:#e8f4f8,stroke:#4a90d9
    style P5 fill:#e8f4f8,stroke:#4a90d9
    style P6 fill:#e8f4f8,stroke:#4a90d9
    style F1 fill:#fde8e8,stroke:#d47474
    style F2 fill:#fde8e8,stroke:#d47474
    style F3 fill:#fde8e8,stroke:#d47474
    style F4 fill:#fde8e8,stroke:#d47474
    style F5 fill:#fde8e8,stroke:#d47474
    style F6 fill:#fde8e8,stroke:#d47474
```

---

## Evaluation: Grading Existing Systems

| System | Level | Evaluator Independence | Modification Surface | Escape Mechanism | Weakness |
|---|---|---|---|---|---|
| **Self-Refine** | 1 | None (same model) | N/A (no persistence) | None | Hallucination barrier limits depth |
| **STaR** | 2 | Partial (answer-key filtering) | Weight-level (fine-tuning) | Rationalization step | Distribution narrowing over iterations |
| **Voyager** | 3 | Partial (env feedback + LLM) | Code-level (skill library) | Automatic curriculum | No skill retirement mechanism |
| **autoresearch** | 4 | Full (immutable `prepare.py`) | Single file (`train.py`) | Stochastic proposals | No explicit local-optima escape |
| **AlphaEvolve** | 4 | Full (automated test suites) | Function-level | Population diversity | Requires massive compute |
| **SICA** | 5 | Partial (LLM overseer) | Full codebase | Archive-based | LLM overseer reintroduces hallucination barrier |

---

## Recommendations

### Short-term: Easy Wins

1. **Replace same-model evaluation with cross-family evaluation.** If your improvement loop uses GPT-4 for both generation and evaluation, switch the evaluator to Claude or Gemini. Expected gain: [10-20x improvement in verifier signal-to-noise ratio](https://arxiv.org/abs/2512.02304). Implements Principle 1.

2. **Add auxiliary metrics to existing loops.** For every self-improvement system in production, add 2-3 metrics beyond the optimization target. Monitor them for regression. Do not optimize them -- just watch. Implements Principle 4.

3. **Fix the compute budget per cycle.** If your improvement cycles currently run "until done," set a wall-clock cap. This makes experiments comparable and prevents verification cost explosion. Implements Principle 2.

### Medium-term: Structural Changes

4. **Move the evaluator out of the modification surface.** If the system can edit the code that evaluates it, your loop is vulnerable to reward hacking. Make the evaluator immutable. autoresearch's `prepare.py` is the template. Implements Principles 1 and 6.

5. **Persist improvements as code, not weights.** If your system currently improves via fine-tuning, consider whether the same improvements could be captured as prompt modifications, tool configurations, or skill library entries. Code-level persistence is inspectable and reversible. Implements Principle 5.

6. **Add population diversity.** If your system uses single-path hill-climbing, maintain an archive of the top-N diverse solutions. Occasionally restart from non-optimal archive members. Implements Principle 3.

### Long-term: Architectural Shifts

7. **Design for the GVU framework.** Explicitly decompose your system into Generator, Verifier, and Updater. Analyze the signal-to-noise ratio of each component. Invest in verifier quality over generator quality -- the Variance Inequality shows this has higher returns.

8. **Build domain-specific oracle verifiers.** For each domain your system operates in, invest in verifiers that produce noiseless signals: test suites, formal proof checkers, simulation environments. The tasks where self-improvement works are the tasks where verification is cheaper than generation.

9. **Implement the ICLR 2026 workshop's improvement-operator card.** For every self-improvement loop, document: objectives, feedback mechanisms, stability constraints, and failure modes. Treat self-improvement as a system that requires the same engineering rigor as any production service.

---

## The Hard Truth

The conditions that make self-improvement most desirable are precisely the conditions where it is formally proven to fail.

Open-ended reasoning, general capabilities, creative problem-solving -- these are the domains where we most want systems to improve themselves. They are also the domains where verification is computationally as hard as generation, where no oracle verifier exists, and where the hallucination barrier is at its strongest. The [formal result](https://arxiv.org/abs/2601.05280) is unambiguous: mutual information with the true distribution cannot increase through self-referential training alone, and when external signal vanishes, distributional means undergo random-walk behavior.

The systems that actually work -- autoresearch, AlphaEvolve -- succeed because they operate in domains where verification is cheap (mathematical loss functions, automated test suites) and the modification surface is small (one file, one function). They are not steps toward general recursive self-improvement. They are demonstrations that **bounded self-improvement within verifiable domains** is tractable and valuable.

Most people in the field get this wrong. They see autoresearch and extrapolate to "AI that improves itself at everything." The correct extrapolation is: AI that improves itself at things where evaluation is cheap, bounded, and independent of the generator. That is a smaller category than "everything" -- but it is also a larger and more useful category than most people realize. Data center scheduling, compiler optimization, algorithm design, hardware layout, training efficiency -- these are all verifiable domains where self-improvement works today. The 0.7% of Google's worldwide compute recovered by AlphaEvolve is not a curiosity. It is the shape of the future: narrow, verifiable, immensely valuable self-improvement operating within carefully bounded modification surfaces.

The bet is not on general self-improvement. The bet is on expanding the set of domains where verification is cheap enough to make the loop work.

---

## Summary Checklist

| Question | Good Answer | Bad Answer |
|---|---|---|
| Is the evaluator structurally independent of the generator? | Different model family, or non-LLM verifier | Same model evaluates its own output |
| Is the compute budget fixed per cycle? | Wall-clock or FLOP cap, all experiments comparable | "Run until it converges" |
| Can the system modify its own evaluator? | No -- evaluator is immutable, outside modification surface | Yes -- system can edit evaluation code |
| Do you track metrics beyond the optimization target? | 2-3 auxiliary metrics monitored for regression | Only the optimization target is measured |
| How do improvements persist? | As code, configs, or skill library entries (inspectable) | As weight changes from fine-tuning (opaque) |
| Is there an escape mechanism for local optima? | Population diversity, archive-based restarts, stochastic proposals | Pure greedy hill-climbing |
| What is the modification surface? | Bounded to specific files/functions, explicitly documented | Unbounded -- system can change anything |
| Has the improvement loop been tested for Goodhart drift? | Auxiliary metrics show no decoupling | Only the primary metric is checked |
| Is there a human review mechanism? | Diffs are small enough to read, improvements are version-controlled | Changes accumulate without review |
| Does the system maintain distribution diversity? | Anchor datasets, diversity monitoring, tail preservation | Pure self-training with no external data |

---

## References

### Research Papers

- [Panickssery et al. -- LLM Evaluators Recognize and Favor Their Own Generations (NeurIPS 2024)](https://arxiv.org/abs/2404.13076): Established 87.8% self-preference rate and causal link between self-recognition and score inflation.
- [On the Limits of Self-Improving in Large Language Models (arXiv 2601.05280)](https://arxiv.org/abs/2601.05280): Formal proofs of entropy decay, information-theoretic stagnation, and conditions for collapse in self-training.
- [When Does Verification Pay Off? (arXiv 2512.02304)](https://arxiv.org/abs/2512.02304): Empirical evidence that same-model verification fails; cross-family verification achieves 10-20x gains.
- [Shumailov et al. -- AI Models Collapse When Trained on Recursively Generated Data (Nature, 2024)](https://www.nature.com/articles/s41586-024-07566-y): Formal theorems on model collapse, tail distribution destruction, and the 10% original data threshold.
- [Chojecki -- Self-Improving AI Agents through Self-Play (GVU Framework)](https://arxiv.org/abs/2512.02731): Generator-Verifier-Updater decomposition, Variance Inequality, and universality proof.
- [Manheim & Garrabrant -- Categorizing Variants of Goodhart's Law (2018)](https://arxiv.org/abs/1803.04585): Four-variant Goodhart taxonomy: regressional, extremal, causal, adversarial.
- [Madaan et al. -- Self-Refine: Iterative Refinement with Self-Feedback (NeurIPS 2023)](https://arxiv.org/abs/2303.17651): Generate-feedback-refine loop achieving ~20% improvement with single LLM.
- [Zelikman et al. -- STaR: Self-Taught Reasoner (NeurIPS 2022)](https://arxiv.org/abs/2203.14465): Bootstrapping reasoning via rationale generation, filtering, and fine-tuning.
- [Wang et al. -- Voyager: An Open-Ended Embodied Agent with Large Language Models (2023)](https://arxiv.org/abs/2305.16291): Skill library architecture for lifelong learning in Minecraft.
- [Robeyns et al. -- SICA: Self-Improving Coding Agent (ICLR 2025 Workshop)](https://arxiv.org/html/2504.15228v2): Self-modifying coding agent improving from 17% to 53% on SWE-Bench Verified.
- [AlphaEvolve -- Strassen Matrix Multiplication Improvement (arXiv 2506.13131)](https://arxiv.org/abs/2506.13131): First improvement over Strassen's 1969 algorithm in 56 years.

### Practitioner Articles and Blogs

- [Lilian Weng -- Reward Hacking in Reinforcement Learning](https://lilianweng.github.io/posts/2024-11-28-reward-hacking/): Comprehensive survey of reward hacking mechanisms, RLHF vulnerabilities, and mitigation strategies.
- [Toby Ord -- The Scaling Paradox](https://www.tobyord.com/writing/the-scaling-paradox): Mathematical analysis of scaling law exponents showing worse-than-polynomial resource requirements.
- [Fortune -- Karpathy's 700-Experiment Autonomous AI Loop](https://fortune.com/2026/03/17/andrej-karpathy-loop-autonomous-ai-agents-future/): Reporting on autoresearch results and adoption.

### Official Documentation and Repositories

- [Karpathy -- autoresearch (GitHub)](https://github.com/karpathy/autoresearch): Source code and experiment discussion threads.
- [autoresearch Discussion #43](https://github.com/karpathy/autoresearch/discussions/43): Detailed session report with 126-experiment results.
- [Google DeepMind -- AlphaEvolve Blog Post](https://deepmind.google/blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/): Official announcement with architecture details and production results.
- [Voyager Project Page](https://voyager.minedojo.org/): Architecture diagrams and benchmark results.
- [ICLR 2026 Workshop on Recursive Self-Improvement](https://recursive-workshop.github.io/): Six-dimensional RSI taxonomy and submission guidelines.
- [Sakana AI -- Darwin Godel Machine](https://sakana.ai/dgm/): Archive-based evolutionary approach to agent self-improvement.

### Related Documents in This Series

- [LLM Role Separation: Executor vs. Evaluator](llm-role-separation-executor-evaluator.md): Seven levels of isolation patterns for breaking generator-evaluator coupling.
- [Evaluation-Driven Development](evaluation-driven-development.md): The measurement infrastructure that self-improvement loops depend on.
- [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md): Why self-enforcement fails and structural alternatives.
