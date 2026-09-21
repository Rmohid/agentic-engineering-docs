# Fine-Tuning for Practitioners: When Prompting Hits a Wall and What to Do About It

Every other document in this suite assumes you are calling an LLM API with a prompt. This one covers what happens when prompting is not enough -- and the disciplined process for knowing when that is actually true.

**Thesis:** Fine-tuning is a data engineering project with a training step bolted on the end, and as of September 2026 the only durable place to run it is an open-weight model.

**Prerequisites:** [Evaluation-Driven Development](evaluation-driven-development.md) (you cannot fine-tune without an eval system), [AI-Native Solution Patterns](ai-native-solution-patterns.md) (the knowledge-versus-behaviour distinction that decides whether tuning is the right tool at all).

**Reading time:** 16 minutes

---

| What teams assume | What actually happens |
|---|---|
| "Fine-tuning is how you teach a model facts" | Facts are a retrieval problem. Tuning a model on facts makes it state them wrongly with more confidence. |
| "We need a frontier model, so we will fine-tune one" | [OpenAI began withdrawing self-serve fine-tuning on 7 May 2026](https://developers.openai.com/api/docs/deprecations); no customer can create a new training job after 6 January 2027. |
| "Fine-tuning is too expensive to try" | LoRA training on an open-weight 9B model is [$0.34 per 1M training tokens at Together AI and $0.50 at Fireworks AI](https://guptadeepak.com/tools/top-8-fine-tuning-model-customization-platforms-2026) (checked 2026-09-18). The dataset, not the training run, is the cost. |
| "Parameter-efficient methods have been superseded" | LoRA is still the default. Full-parameter training is priced at exactly twice the LoRA rate where both are offered, and every reference implementation starts at LoRA. |
| "Training loss falling means the tune worked" | Training loss is not a result. If your first LoRA run does not move the evaluation score, the problem is the dataset, not the method. |
| "A tuned proprietary model is a safe place to invest" | Proprietary fine-tuning is terminal: you hold no weights and no adapter, so the withdrawal is a lock-in event rather than a migration. |

---

## The Tension: Fine-Tuning Solves Real Problems -- But Most Teams Do It Too Early

There is a seductive logic to fine-tuning: your LLM is not behaving how you want, so you train it to behave differently. The logic is sound. The timing almost never is.

[Hamel Husain](https://hamel.dev/blog/posts/fine_tuning_valuable.html) frames the prerequisite bluntly: "You should definitely try not to fine-tune first. You need to prove to yourself that you should fine-tune." The purpose of prompt engineering is not to avoid fine-tuning forever -- it is to stress-test your evaluation system before you invest in training. If you cannot measure whether your current system works, you cannot measure whether fine-tuning improved it.

The [AI-Native Solution Patterns](ai-native-solution-patterns.md) document in this suite introduces the knowledge-behavior distinction: RAG fills knowledge gaps (facts the model does not have), while fine-tuning fills behavior gaps (patterns the model cannot consistently reproduce through prompting alone). This is correct as a decision framework. What it does not cover is the execution -- the actual process of curating data, choosing a training method, running the training, and evaluating the result. That is what this document covers.

| Approach | Solves | Time to Ship | Cost to Try | When It Fails |
|---|---|---|---|---|
| **Prompt engineering** | Task framing, output format, reasoning strategy | Hours | Free (API calls only) | Inconsistent behavior at scale, complex multi-constraint tasks |
| **RAG** | Knowledge gaps, current data, source attribution | Days-weeks | Moderate (embedding + retrieval infra) | Behavior/style problems, format consistency |
| **Fine-tuning** | Behavioral consistency, domain patterns, cost reduction | Weeks | High (data curation + training + eval) | Knowledge gaps, volatile requirements, insufficient data |

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a1a', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#f0e8f8', 'tertiaryColor': '#e8f8e8', 'edgeLabelBackground': '#ffffff'}}}%%
graph TD
    subgraph Decision["When to Fine-Tune"]
        style Decision fill:#e8f4f8,stroke:#4a90d9
        Q1{"Does prompting solve<br/>the task at all?"}
        Q1 -->|No| STOP["Stop. Fix the task<br/>definition first."]
        Q1 -->|"Yes, but inconsistently"| Q2{"Is the gap about<br/>knowledge or behavior?"}
        Q2 -->|Knowledge| RAG["Use RAG"]
        Q2 -->|Behavior| Q3{"Do you have 200+<br/>curated examples?"}
        Q3 -->|No| CURATE["Curate data first.<br/>Use the eval system."]
        Q3 -->|Yes| Q4{"Is the behavior<br/>stable over time?"}
        Q4 -->|"No, changes often"| PROMPT["Stay with prompting.<br/>Fine-tuning is too rigid."]
        Q4 -->|"Yes, stable"| FT["Fine-tune."]
    end
```

---

## Failure Taxonomy: How Fine-Tuning Goes Wrong

### Failure 1: The Template Mismatch

[Hamel Husain calls this](https://parlance-labs.com/education/fine_tuning_course/workshop_1.html) "the biggest nightmare" in fine-tuning. Your training data uses one chat template format; your inference pipeline uses another. The model produces garbage -- not because training failed, but because the input format at inference does not match what it learned.

**Why it happens:** Chat templates (the wrapping around user/assistant turns) vary between frameworks, providers, and even library versions. If you train with `<|im_start|>user` tokens but infer with `[INST]` tokens, the model has never seen the inference format.

**How to prevent it:** Always verify template parity between training and inference before diagnosing any other problem. Use the same tokenizer and template library for both.

### Failure 2: Catastrophic Forgetting

The model excels at your target task but loses previously learned general capabilities. You fine-tune a model to extract medical entities, and it can no longer write coherent English.

**Why it happens:** Fine-tuning shifts model weights toward your training distribution. Narrow data shifts weights far from the general distribution. [Research confirms](https://www.legionintel.com/blog/navigating-the-challenges-of-fine-tuning-and-catastrophic-forgetting) that both naive fine-tuning and LoRA cause substantial performance drops on prior tasks -- LoRA reduces but does not eliminate the problem.

**How to prevent it:** Always evaluate on a broad benchmark suite (not just your target task) before and after fine-tuning. Use lower learning rates, fewer epochs, and LoRA to minimize drift.

### Failure 3: Overfitting the Training Set

Training loss drops. Validation performance plateaus or degrades. The model memorizes your examples instead of learning generalizable patterns.

**Why it happens:** Too many epochs on too little data. Too-high learning rate. Insufficient data diversity. [Sebastian Raschka found](https://magazine.sebastianraschka.com/p/practical-tips-for-finetuning-llms) that multi-epoch training on static datasets reliably causes degradation -- single epoch is preferred.

**How to prevent it:** Use a held-out validation set. Monitor validation loss, not just training loss. Stop at one epoch unless you have strong evidence that more helps.

### Failure 4: Capability Regression

The fine-tuned model performs better on the target task but worse on adjacent capabilities you still need. You fine-tune for structured JSON extraction, and the model's natural language explanations become stilted.

**Why it happens:** The training signal biases the model toward the narrow task distribution. This is distinct from catastrophic forgetting -- the model retains general capabilities but degrades on specific adjacent skills.

**How to prevent it:** Identify adjacent capabilities you need to preserve before training. Include them in your eval suite. If regression is detected, add representative examples of those capabilities to the training mix.

### Failure 5: Evaluation-Free Fine-Tuning

The team collects data, runs training, and ships the fine-tuned model without measuring whether it actually improved anything. They rely on training loss curves and "it looks better" spot checks.

**Why it happens:** [Hamel Husain's field guide](https://hamel.dev/blog/posts/evals/) identifies this as the most common failure: teams treat evaluation as optional overhead rather than a prerequisite. Fine-tuning without evaluation is guessing with expensive compute.

**How to prevent it:** Establish evaluation before fine-tuning begins. The eval system generates fine-tuning data nearly automatically -- unit tests and model critiques filter and curate training examples.

### Failure 6: Reward Hacking (DPO/RLHF)

The model learns to exploit the preference signal rather than genuinely improve. It produces outputs that score well on the preference model but are not actually better.

**Why it happens:** Low DPO beta values allow aggressive adaptation that overfits to superficial preference patterns. The reward model captures correlation, not causation.

---

## The Training Method Spectrum

Fine-tuning is not one technique. It is a spectrum from lightweight adaptation to full alignment training. Most production use cases need only the left side.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a1a', 'primaryBorderColor': '#4a90d9', 'lineColor': '#4a90d9', 'secondaryColor': '#f0e8f8', 'tertiaryColor': '#e8f8e8', 'edgeLabelBackground': '#f5f5f5'}}}%%
graph LR
    subgraph Methods["Training Methods: Cost and Complexity"]
        style Methods fill:#e8f4f8,stroke:#4a90d9
        SFT["SFT<br/><i>Format + task structure</i><br/>Cost: $</i>"]
        DPO["DPO<br/><i>Preference alignment</i><br/>Cost: $$"]
        RLHF["RLHF<br/><i>Maximum alignment control</i><br/>Cost: $$$"]
        FULL["Full Fine-Tune<br/><i>All parameters</i><br/>Cost: $$$$"]
    end
    SFT --> DPO --> RLHF --> FULL
```

### SFT (Supervised Fine-Tuning)

Teaches the model a task structure by showing it input-output examples. Always the first stage. Stable, cheap, fast. Effective for: output format consistency, instruction following, domain-specific extraction, distillation from a larger model.

### DPO (Direct Preference Optimization)

Refines subjective preferences without a separate reward model. [OpenAI recommends](https://developers.openai.com/cookbook/examples/fine_tuning_direct_preference_optimization_guide) running SFT first, then DPO from the SFT checkpoint. 40-75% cheaper than RLHF. Effective for: style/tone alignment, brand voice, compliance requirements, resolving tradeoffs (concise vs. thorough).

### RLHF (Reinforcement Learning from Human Feedback)

Maximum alignment control via a trained reward model plus PPO optimization. Only 8% unsafe outputs vs DPO's 10% in adversarial testing. Reserved for safety-critical applications and teams with frontier-lab resources. Most production teams do not need this.

**The practical pipeline:** SFT first (establishes structure) -> DPO second (refines preferences). This two-stage approach is the [OpenAI-recommended default](https://developers.openai.com/cookbook/examples/fine_tuning_direct_preference_optimization_guide).

---

## LoRA: The Production Default

LoRA (Low-Rank Adaptation) trains 0.1-1% of model parameters by injecting small trainable matrices into frozen model layers. Results are nearly indistinguishable from full fine-tuning for most tasks.

### Recommended Starting Configuration

Based on [Sebastian Raschka's benchmarks](https://magazine.sebastianraschka.com/p/practical-tips-for-finetuning-llms):

| Parameter | Recommended Value | Why |
|---|---|---|
| Rank (r) | 16 | Good performance-cost tradeoff. r=256 is marginally better but 15x more params. |
| Alpha | 32 (2x rank) | Standard ratio. Controls learning rate scaling. |
| Target modules | All linear layers | Going from K/V-only to all layers meaningfully improves quality for only 2.4GB more memory. |
| Epochs | 1 | Multi-epoch on static data causes degradation. |
| Learning rate | 2e-4 (SFT), 5e-6 (DPO) | DPO requires much lower learning rate. |
| Optimizer | AdamW | Choice barely matters. SGD saves ~3.4GB only at very large ranks. |

### QLoRA Tradeoff

QLoRA quantizes the base model to 4-bit before applying LoRA, saving 33% memory at the cost of 39% longer training time. Quality impact is negligible.

| Model Size | LoRA Memory | QLoRA Memory | Training Time Impact |
|---|---|---|---|
| 7B | ~21GB | ~14GB | +39% |
| 13B | ~38GB | ~26GB | +39% |
| 70B | 4x A100 80GB | 2x A100 80GB | +39% |

QLoRA enables fine-tuning on consumer hardware (Mac M2/M3 with 32GB+, single A100).

---

## Data Curation: Quality Over Quantity

The LIMA paper demonstrated that 1,000 curated examples performed similarly to 50,000 synthetic ones. Every training example shifts model parameters -- bad examples shift them in the wrong direction.

### How Much Data You Need

| Task Complexity | Examples Needed |
|---|---|
| Simple classification | 100-300 per category |
| Structured data extraction | 200-500 |
| Content generation / style | 500-2,000 |
| Complex domain adaptation | 1,000-5,000 |
| Absolute minimum | 200 |

Below ~100 examples, you are doing few-shot prompting with extra steps.

### The Distillation Workflow

Use a powerful model to generate training data, then fine-tune a cheaper model on those outputs. [TensorZero reports](https://www.tensorzero.com/blog/distillation-programmatic-data-curation-smarter-llms-5-30x-cheaper-inference) 5-30x cost reductions across production tasks:

| Task | Student Model | Cost Reduction | Success Rate |
|---|---|---|---|
| Data extraction (NER) | Gemini Flash Lite | 31x cheaper | ~95% |
| Navigation agent | GPT-4.1 nano | 21x cheaper | ~95% |
| Agentic RAG | GPT-4.1 mini | 5.7x cheaper | ~47% |
| Tool use (retail) | Gemini Flash | 9.4x cheaper | ~82% |

The distillation process: (1) collect 300-700 successful conversations from the expensive model, (2) curate aggressively using your eval system (only successful episodes), (3) split 80/20 train/validation, (4) fine-tune the student model, (5) evaluate student against teacher on held-out data.

### Common Data Mistakes

1. **Template inconsistency** -- mismatch between training and inference chat templates (the #1 practical failure)
2. **Training on noisy logs** -- 10,000 well-labeled examples outperform 100,000 noisy ones
3. **Building "ask anything" datasets** -- creates mismatched expectations and massive failure surfaces. Scope narrowly.
4. **Ignoring distribution mismatch** -- training data must represent your actual production distribution
5. **Using instruction-tuned models as base for narrow domains** -- base models give more control over templates

---

## Choosing a Base Model (September 2026)

By September 2026 the open-weight frontier is Chinese, and Llama is no longer in the conversation at the top. The leaders are DeepSeek V4-Pro (the strongest published open coding numbers), GLM-5.2 (tuned for long-horizon agentic work), Qwen3.5, Kimi, and MiniMax M3, with OpenAI's gpt-oss-120b and Google's Gemma 4 as the main Western open-weight options. There is no single best model; the honest answer is task-dependent.

Two things matter more than the leaderboard for a fine-tuning decision:

1. **The licence.** Apache-2.0 models (Gemma 4, Qwen3.5, GLM-5, gpt-oss-120b) carry no usage restrictions. Llama 4 carries a 700-million-monthly-active-user cap. Read the licence before you train on it, because the licence follows the weights you ship.
2. **The provider's published training price.** A model you cannot train cheaply is a model you will not iterate on. The price list below is the real constraint on how many experiment cycles you get.

## What Fine-Tuning Actually Costs (September 2026)

The training run is the cheapest part, and it is the part everyone budgets for. Every rate below was read from the provider's own pricing page in September 2026.

### Managed API Pricing (per 1M training tokens)

| Provider / model tier | LoRA SFT | Full-parameter SFT | Notes |
|---|---|---|---|
| Fireworks AI, up to 16B | $0.50 | $1.00 | $3.00 at 16.1-80B, $6.00 at 80-300B, $10.00 above 300B |
| Together AI, Qwen3.5 9B | $0.34 | -- | DPO is 2-4x the SFT rate; per-job minimum $4 |
| Together AI, Gemma 4 31B | $1.05 | -- | |
| Together AI, Llama 3.3 70B | $2.03 | -- | |
| Together AI, DeepSeek-V3.1 | $7.00 | -- | |
| OpenAI gpt-4.1 / gpt-4o | -- | $25.00 | $3.00/$12.00 and $3.75/$15.00 per 1M input/output tokens to serve, while the platform lasts |
| OpenAI gpt-4o-mini | -- | $3.00 | $0.30/$1.20 per 1M tokens to serve |
| OpenAI o4-mini (reinforcement fine-tuning) | -- | $100.00/hour | Billed by the hour, not by the token |
| AWS Bedrock (Llama 2 13B) | $1.49 | -- | Custom models require Provisioned Throughput: $23.50 per model-unit hour with no commitment, about $17,000 a month |
| Unsloth / Axolotl on your own GPU | $0 | $0 | Apache-2.0 tooling; you pay only for the hardware |
| Google Vertex AI (Gemini) | rate not quotable | -- | Vertex publishes supervised tuning per 1M tokens, but the pricing table did not render a figure when checked on 2026-09-18 -- confirm in your quote |

Two facts change the arithmetic.

**OpenAI is withdrawing self-serve fine-tuning.** On 7 May 2026 OpenAI blocked new organisations from creating training jobs; on 2 July 2026 it blocked organisations with no recent fine-tuned inference; and on 6 January 2027 no customer can create a new fine-tuning job at all. Inference on existing fine-tuned models continues only until the underlying base model is deprecated. OpenAI's stated reason is that newer base models follow instructions and formats well enough to make much of the process unnecessary. A team that tuned a proprietary model holds no weights and no adapter, so this is a terminal lock-in, not a migration. Anthropic never opened fine-tuning through its own API at all. For any new project in 2026, frontier proprietary models are not a fine-tuning target and open-weight models are.

**LoRA has not been displaced.** Every open-weight provider prices LoRA first and full-parameter training as a multiple of it, and the reference implementations still default to LoRA at rank 32. Nothing newer has replaced the method. What changed since early 2026 is price, not technique.

**Worked example:** 20,000 examples at 500 tokens for 3 epochs is 30M training tokens. On Fireworks at $3.00 per 1M for a 70B LoRA run that is about $90; on Together at $2.03 per 1M for Llama 3.3 70B it is about $61. Serving a fine-tuned open-weight model is charged at the base model's rate -- there is no inference premium for having tuned it.

### Self-Hosted GPU Costs

Paying per token is a convenience, not a saving. Renting the hardware is cheaper at sustained utilisation, and the gap is large enough to change the decision.

| Route | Published rate (September 2026) | What it buys |
|---|---|---|
| Together AI, dedicated HGX H100 | $3.99/GPU-hour (promotional through 09/30/26; list $5.49) | The cheapest published dedicated rate for open-weight training |
| Fireworks AI, on-demand H100 80GB | $8.00/hour | Billed per second; B200 $13.00/hour, B300 $15.00/hour |
| Your own machine (QLoRA, 32GB+ unified memory) | free | A 7B LoRA run in single-digit hours |

At roughly the same token volume, per-token training costs several times what the equivalent rented GPU hours cost, and the multiple holds as the model size grows. The trade is orchestration: per-token pricing removes the scheduling work, and you pay for that convenience per token.

---

## The Hard Truth

99% of fine-tuning effort is data assembly, and most teams are not ready for it. Fine-tuning is not a model problem -- it is a data engineering problem with a model training step at the end. Teams that have a mature eval system can generate fine-tuning data nearly automatically: the eval system identifies successes, unit tests filter for quality, and model critiques curate examples. Teams without an eval system are guessing about what to train on, guessing about whether training helped, and shipping models based on vibes.

The uncomfortable reality: if your eval system is not good enough to generate training data, it is not good enough to validate a fine-tuned model. Fix the eval system first. The fine-tuning will follow naturally.

---

## Field Notes from an Operating Estate

**September 2026 -- the estate has not fine-tuned a model, and that is itself a finding.** A practitioner operating an estate of a dozen agent harnesses has closed every quality gap it has met by other means: routing a task to a different model, adding retrieval, tightening the output contract, or adding a deterministic check. The run record holds no fine-tune, because no gap has survived those four steps and then justified assembling a labelled dataset. The honest reading is not that fine-tuning does not work. It is that the steps above fine-tuning on this document's own decision tree keep being sufficient, and that the dataset -- not the training run -- is what would make the exercise expensive.

**September 2026 -- cost control came from routing, not from training.** When a task turned out to be too slow or too costly, the estate's answer was to assign it to a cheaper model tier behind a routing layer, not to distil a student model. Routing is reversible in one config change; a distilled student is a new artifact to evaluate, serve, and eventually retire. Where distillation would be justified, the rule the estate applies to any cost change applies: a measured delta on real traffic, never an estimate.

---

## Summary Checklist

| Question | Good Answer | Bad Answer |
|---|---|---|
| Have you tried prompt engineering first? | Yes -- we documented what works and what does not | No -- we went straight to fine-tuning |
| Do you have an eval system? | Yes -- with automated metrics and held-out test data | No -- we spot-check outputs manually |
| Is your gap about knowledge or behavior? | Behavior -- consistent format, style, domain patterns | Knowledge -- facts the model does not have (use RAG) |
| Do you have 200+ curated examples? | Yes -- filtered by our eval system for quality | No -- we scraped logs without curation |
| Are your requirements stable? | Yes -- the target behavior will not change monthly | No -- requirements shift frequently (stay with prompting) |
| Did you verify template parity? | Yes -- training and inference use identical chat templates | No -- we used different frameworks for training and serving |
| Did you evaluate on a broad benchmark? | Yes -- target task AND adjacent capabilities | No -- we only tested the fine-tuned task |
| Are you training for one epoch? | Yes -- multi-epoch on static data causes degradation | No -- we trained for 5+ epochs to push loss down |

---

## References

### Practitioner Guides
- [Hamel Husain: When Is Fine-Tuning Valuable?](https://hamel.dev/blog/posts/fine_tuning_valuable.html) -- Prerequisites and decision framework for fine-tuning
- [Sebastian Raschka: Practical Tips for Fine-Tuning LLMs](https://magazine.sebastianraschka.com/p/practical-tips-for-finetuning-llms) -- LoRA/QLoRA benchmarks, rank settings, memory tradeoffs
- [Hamel Husain: Fine-Tuning Course Workshop](https://parlance-labs.com/education/fine_tuning_course/workshop_1.html) -- The template mismatch problem and data curation
- [Chip Huyen: Building LLM Applications for Production](https://huyenchip.com/2023/04/11/llm-engineering.html) -- Prompt-first philosophy, distillation economics
- [Hamel Husain: Your AI Product Needs Evals](https://hamel.dev/blog/posts/evals/) -- Three-level eval framework and how eval generates fine-tuning data

### Technical References
- [OpenAI API Deprecations](https://developers.openai.com/api/docs/deprecations) -- The self-serve fine-tuning wind-down: notice on 7 May 2026, complete block on new training jobs on 6 January 2027
- [Together AI pricing](https://www.together.ai/pricing) -- Per-1M-token training rates by model size, checked September 2026
- [Fireworks AI](https://fireworks.ai/) -- LoRA and full-parameter training, plus on-demand GPU rates; the training rates quoted above were read from its pricing page on 2026-09-18 (the pricing page itself was returning a server error when re-checked, so the independent comparison below is the citable source)
- [Top 8 Fine-Tuning and Model Customization Platforms 2026](https://guptadeepak.com/tools/top-8-fine-tuning-model-customization-platforms-2026) -- Independent comparison, with every price read from the provider's own page on 2026-09-18
- [The Best Open-Source LLMs in 2026](https://irenictech.com/blog/best-open-source-llms-2026) -- Open-weight landscape: DeepSeek, GLM, Qwen, Kimi, MiniMax
- [12 Best Open Source AI Models 2026](https://primeaicenter.com/best-open-source-ai-models) -- Licence tiers across open-weight models, including the Llama 4 user cap
- [OpenAI: Fine-Tuning with DPO Guide](https://developers.openai.com/cookbook/examples/fine_tuning_direct_preference_optimization_guide) -- SFT vs DPO decision matrix; note that the platform this guide describes is being withdrawn
- [TensorZero: Distillation Results](https://www.tensorzero.com/blog/distillation-programmatic-data-curation-smarter-llms-5-30x-cheaper-inference) -- Production distillation achieving 5-30x cost reduction
- [Catastrophic Forgetting in Fine-Tuned LLMs](https://www.legionintel.com/blog/navigating-the-challenges-of-fine-tuning-and-catastrophic-forgetting) -- Research on LoRA's limitations against forgetting

### Related Documents in This Series
- [AI-Native Solution Patterns](ai-native-solution-patterns.md) -- The knowledge-behavior gap decision framework
- [Evaluation-Driven Development](evaluation-driven-development.md) -- Building the eval system that fine-tuning depends on
- [Cost Engineering for LLM Systems](cost-engineering-for-llm-systems.md) -- Distillation as a cost optimization strategy
- [Structured Output and Parsing](structured-output-and-parsing.md) -- Schema enforcement that fine-tuning can complement

---

*Last reviewed: September 2026. Changed in this revision: the cost table was re-read from provider pricing pages on 2026-09-18 and the stale Llama 3.1, Mistral 7B, and GPT-4o rows were replaced; the OpenAI self-serve fine-tuning wind-down and its 6 January 2027 terminal date were added; an open-weight base-model section was added; and the myth-versus-reality table, field notes, and front matter block were added.*
