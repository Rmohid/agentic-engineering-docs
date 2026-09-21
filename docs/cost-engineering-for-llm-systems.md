# Cost Engineering for LLM Systems: Why Your AI Budget Is a Lie and How to Fix It

**Thesis:** LLM cost is an architectural property, not a pricing problem -- the bill is set by how many times your system calls a model, not by what a token costs.

**Prerequisites:** [LLM Fundamentals for Practitioners](llm-fundamentals-for-practitioners.md) (token mechanics, model tiers), [AI-Native Solution Patterns](ai-native-solution-patterns.md) (the router pattern), [Observability and Monitoring](observability-and-monitoring.md) (the telemetry that makes spend attributable).

**Reading time:** 21 minutes

---

Every team building with LLMs eventually discovers the same uncomfortable truth: the API call that costs $0.002 in development costs $2.00 in production -- not because prices changed, but because nobody modeled how costs compound across pipelines, retries, agent loops, and scale. Cost engineering is not optimization. It is the discipline of making LLM systems economically viable before they bankrupt you.

| What teams assume | What actually happens |
|---|---|
| "Prices keep falling, so our bill will fall too" | Per-token prices fell roughly 100x in 2.5 years while agentic workloads consume 5-30x more tokens per task than a chat exchange ([Gartner](https://www.gartner.com/en/newsroom/press-releases/2026-03-25-gartner-predicts-that-by-2030-performing-inference-on-an-llm-with-1-trillion-parameters-will-cost-genai-providers-over-90-percent-less-than-in-2025)) |
| "One strong model for everything is simpler" | Routing a single workload across tiers cuts spend 50-85% with no measured quality loss ([RouteLLM](https://arxiv.org/abs/2406.18665)) |
| "A per-token price cap bounds my bill" | A price cap bounds the *rate*, not dollars per call; without an output-token bound a call can still be expensive ([OpenRouter](https://openrouter.ai/docs/features/model-routing)) |
| "Cached input is a 50% discount" | The newest flagship tiers read cached input at 10% of the input rate -- 90% off, not 50% ([BenchLM](https://benchlm.ai/llm-pricing)) |
| "Batch APIs are for experiments" | Batch is a straight 50% discount for a 24-hour completion window, available on the highest-volume workloads |
| "If a budget cap is set, we cannot overspend" | A cap that reads a counter which is not monotonic silently stops braking (see Failure 7) |
| "Cost per request is the metric" | Cost per *successful task* is the metric; a cheap call that fails and retries is the expensive one |

## The Core Tension

LLM pricing looks simple on a provider's pricing page. It is not. The core tension in LLM cost engineering is that **the tokens you pay the most for are the ones you control the least**.

Every major provider prices input and output tokens differently, and on the September 2026 price lists output tokens cost 5-6x more than input tokens on most current models. This asymmetry exists because output tokens require sequential autoregressive generation (each token depends on the previous one), while input tokens can be processed in parallel. The economics of silicon enforce this ratio.

| Provider | Model | Input / MTok | Output / MTok | Cached Input / MTok | Output Multiplier |
|---|---|---|---|---|---|
| OpenAI | GPT-6 Astra | $10.00 | $50.00 | $1.00 | 5.0x |
| OpenAI | GPT-5.6 Sol | $4.00 | $20.00 | $0.40 | 5.0x |
| OpenAI | GPT-5.6 Terra | $2.00 | $12.00 | $0.20 | 6.0x |
| OpenAI | GPT-5.6 Luna | $0.20 | $1.20 | $0.02 | 6.0x |
| Anthropic | Claude Fable 5.1 | $10.00 | $50.00 | $0.25 | 5.0x |
| Anthropic | Claude Opus 5 | $5.00 | $25.00 | $0.50 | 5.0x |
| Anthropic | Claude Sonnet 5 | $2.00 | $10.00 | $0.20 | 5.0x |
| Anthropic | Claude Haiku 4.5 | $1.00 | $5.00 | $0.10 | 5.0x |
| Google | Gemini 3.1 Pro | $2.00 | $12.00 | $0.20 | 6.0x |
| Google | Gemini 3.8 Flash | $0.75 | $3.75 | $0.07 | 5.0x |
| Google | Gemini 3.5 Flash-Lite | $0.30 | $2.50 | $0.03 | 8.3x |
| DeepSeek | DeepSeek V4 Pro | $0.43 | $0.87 | $0.00 | 2.0x |
| Z.ai | GLM-5.2 | $1.40 | $4.40 | -- | 3.1x |

*Sources: [BenchLM pricing comparison, verified 18 September 2026](https://benchlm.ai/llm-pricing), [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing), [OpenAI API pricing](https://openai.com/api/pricing/), [Google AI pricing](https://ai.google.dev/pricing)*

Prices on this list move every quarter, and a stale table is worse than no table. Two structural facts outlast any individual number. The *ratio* between the cheapest and the most expensive tier is roughly 50x on input and 40x on output, and it has been stable while absolute prices fall. And the cheapest model is not necessarily the cheapest completed task: a low input rate loses when the model writes long answers, misses the cache, or needs more retries to pass the same test ([BenchLM](https://benchlm.ai/llm-pricing)).

The multiplier matters because you cannot predict output length. You control your prompt; you do not control the response length. A request that should return 200 tokens of JSON can return 2,000 tokens of explanation, and that 10x overshoot is a 10x overshoot on your most expensive token type.

This asymmetry compounds across architectural patterns. A single LLM call has a predictable cost envelope. A pipeline of five calls multiplies that envelope. An agent with tool-calling loops makes the envelope unbounded.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#5b8a9a', 'lineColor': '#5b8a9a', 'secondaryColor': '#f0e6d3', 'tertiaryColor': '#e8e8e8', 'clusterBkg': '#f5f5f5', 'edgeLabelBackground': '#f5f5f5'}}}%%
graph LR
    subgraph Cost["Cost Per Request by Pattern"]
        A["Single Call<br/>$0.001-$0.01"] --> B["Pipeline<br/>3-5 calls<br/>$0.005-$0.05"]
        B --> C["Router + Handlers<br/>2-4 calls<br/>$0.003-$0.03"]
        C --> D["Orchestrator<br/>5-20 calls<br/>$0.02-$0.50"]
        D --> E["Agent Loop<br/>10-100+ calls<br/>$0.10-$50.00"]
    end
```

The difference between a single augmented call and an autonomous agent is not 2x or 5x. It is **10-100x** on the same task ([Moltbook-AI](https://moltbook-ai.com/posts/ai-agent-cost-optimization-2026)). Teams that architect for agents without modeling this cost curve discover it in their first invoice.

---

## Failure Taxonomy

Cost failures in LLM systems are not random. They follow predictable patterns, each with distinct root causes and signatures.

### Failure 1: The Runaway Agent

An agent enters an infinite or near-infinite loop, burning tokens without producing useful output. This is the most dramatic failure mode and the one that generates horror stories.

**What it looks like:** Your daily cost jumps from $100 to $10,000 overnight. Monitoring (if you have it) shows a single agent session generating thousands of API calls.

**Why it happens:** Agent architectures have no inherent termination guarantee. The model decides when to stop. If the model's reasoning enters a cycle -- retrying a failed tool call, re-evaluating the same evidence, or ping-ponging between sub-agents -- there is no structural mechanism to break the loop unless you built one.

**Concrete example:** A multi-agent research tool built on LangChain had four agents (Research, Analysis, Verification, Summary). The Analyzer and Verifier entered a recursive loop through agent-to-agent messaging. The loop ran **11 days undetected**. Weekly costs escalated: $127, $891, $6,240, $18,400. Total: [$47,000](https://techstartups.com/2025/11/14/ai-agents-horror-stories-how-a-47000-failure-exposed-the-hype-and-hidden-risks-of-multi-agent-systems/). Root cause analysis identified zero step limits, zero cost ceilings, zero real-time monitoring, and zero alerting.

### Failure 2: The Model Mismatch

Using a frontier model for tasks that a budget model handles equally well. This is the most common cost failure and the easiest to fix, yet most teams never address it.

**What it looks like:** Every request hits the most expensive model regardless of complexity. Your cost-per-request is consistent but uniformly high.

**Why it happens:** Teams pick one model during development and never revisit. The model that works for the hardest 5% of inputs is used for the easiest 95%. A simple classification task that a $0.20/MTok model handles is sent to a $10/MTok model -- a 50x cost premium for equivalent accuracy.

**Concrete example:** A customer service system routes all queries to Claude Sonnet 5. Evaluation shows that 70% of queries are simple FAQ lookups where Haiku 4.5 produces identical quality. Switching those 70% to Haiku saves **$12,000/month** on a 50K query/month workload ([Moltbook-AI](https://moltbook-ai.com/posts/ai-agent-cost-optimization-2026)). The team was paying 3x what the workload required.

### Failure 3: The Cache Miss

Sending identical or semantically equivalent prompts to the API repeatedly, paying full price each time for responses that should have been cached.

**What it looks like:** High request volume with low response variance. Many requests produce near-identical outputs.

**Why it happens:** LLM calls look like function calls, so developers treat them as stateless. They do not instrument cache hit rates because the concept does not occur to them. In enterprise workloads, [31% of queries show semantic similarity](https://redis.io/blog/llm-token-optimization-speed-up-apps/) sufficient for caching.

**Concrete example:** A document QA system answers questions about 10 internal documents. Each question sends the full 20K-token document as context. 1,000 queries/day, 60% of which are about the same three documents. Without prompt caching, the system pays full input token price for each request. With Anthropic's prompt caching (cache reads at 10% of base price), annual savings exceed $20,000 ([Introl](https://introl.com/blog/prompt-caching-infrastructure-llm-cost-latency-reduction-guide-2025)).

### Failure 4: The Output Explosion

Failing to constrain output token generation, allowing the model to produce verbose responses that cost 5-6x more per token than the input that triggered them.

**What it looks like:** Responses are longer than necessary. JSON outputs include explanatory text. Summaries are longer than the source material.

**Why it happens:** Without `max_tokens` limits, clear formatting instructions, or structured output schemas, the model defaults to being helpful -- which means verbose. Each unnecessary output token costs 5-6x what an input token costs.

**Concrete example:** A data extraction pipeline asks the model to extract five fields from a document. Without structured output constraints, the model returns the five fields plus a 500-word explanation of its reasoning. The explanation costs more than the useful output. Adding `"respond only with JSON, no explanation"` and setting `max_tokens: 200` cuts output tokens by 80%.

### Failure 5: The Context Bloat

Accumulating conversation history, system prompts, and retrieved documents without management, pushing input token counts to the context window ceiling.

**What it looks like:** Early requests in a session are cheap. Late requests are expensive. Long sessions cost disproportionately more than short ones.

**Why it happens:** Each turn in a conversation appends the full history. A 20-turn conversation with 500 tokens per turn sends 10,000 tokens of history on the final call -- plus the system prompt, plus any RAG context. The input token cost grows quadratically with conversation length.

**Concrete example:** A coding assistant with a 4,000-token system prompt and RAG context averaging 2,000 tokens starts each conversation at 6,000 input tokens. By turn 20, input tokens reach 26,000. If the user asks 50 questions, the final call sends 56,000 input tokens. Implementing a sliding window (keep last 10 turns) plus progressive summarization (summarize older turns) reduces late-session input by 50-70% ([Redis](https://redis.io/blog/llm-token-optimization-speed-up-apps/)).

### Failure 6: The Invisible Spend

No cost attribution, no per-feature tracking, no per-user metering. Total spend is known; where it goes is not.

**What it looks like:** The monthly bill is $15,000. Nobody knows whether that is search, summarization, or the internal chatbot. Nobody knows if one user is consuming 80% of the budget.

**Why it happens:** Teams track aggregate API spend but do not instrument individual features, users, or request types. Without attribution, optimization is impossible because you cannot identify what to optimize.

**Concrete example:** A SaaS platform discovers its $47,000 monthly LLM bill is 60% attributable to a single power user running automated queries. Without per-user metering, this went undetected for three months. Implementing per-user spend tracking and rate limits reduced the bill to [$28,000](https://www.pluralsight.com/resources/blog/ai-and-data/how-cut-llm-costs-with-metering).

---

### Failure 7: The Dead Brake

A spending brake that reads a counter which is not monotonic goes silently negative and stops braking. This is the failure that leaves every other control looking present while doing nothing.

**What it looks like:** The budget check is wired, the ceiling is configured, the alert thresholds are set -- and no run is ever stopped. The monthly total is higher than the cap can explain, and every individual component looks correct.

**Why it happens:** Spend is measured by subtracting a start value from a current value. If the field being read is a *windowed* counter -- a rolling monthly total, a period-to-date figure, a balance that gets topped up -- it can fall during a run. The subtraction then yields a negative number from the first re-read, and a negative number never reaches a positive threshold. The brake is dead from the first check, whatever the run spends.

**Concrete example:** A nightly batch job computed its in-run spend as `usage_monthly_now - usage_monthly_at_start` and stopped the run when that delta reached its allowance. On a measured run, the windowed counter fell by 149.89 during the job while the money actually spent -- read from the remaining-credit field on the *same* response payload -- was 0.109. The delta was negative, the stop condition could never fire, and the only remaining brake was the pre-run arithmetic, which decides once at the start. Two fields on one payload disagreed about which one carried the spend, and the consumer had picked the non-monotonic one.

**The fix, and the general rule:** brake on a quantity that is monotonic within the accounting period -- a remaining balance that only falls, a cumulative counter that only rises -- and assert that monotonicity rather than assuming it. A pre-run decision is not an in-run brake: if the only check happens before the run, a run that overspends mid-flight is never stopped.

---

## The Cost Maturity Spectrum

Organizations progress through predictable stages of cost engineering maturity. Each level addresses specific failure modes from the taxonomy above.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#5b8a9a', 'lineColor': '#5b8a9a', 'secondaryColor': '#f0e6d3', 'tertiaryColor': '#e8e8e8', 'clusterBkg': '#f5f5f5', 'edgeLabelBackground': '#f5f5f5'}}}%%
graph TD
    subgraph Maturity["Cost Engineering Maturity"]
        L1["Level 1: Blind<br/>No tracking beyond<br/>aggregate monthly bill"] --> L2["Level 2: Metered<br/>Per-request cost tracking<br/>Token counting before send"]
        L2 --> L3["Level 3: Optimized<br/>Caching, model routing<br/>Output constraints"]
        L3 --> L4["Level 4: Governed<br/>Budget caps, circuit breakers<br/>Per-user limits, alerting"]
        L4 --> L5["Level 5: Autonomous<br/>Dynamic model selection<br/>Cost-quality Pareto frontier"]
    end
```

| Level | Characteristics | Failure Modes Addressed | Typical Cost Reduction |
|---|---|---|---|
| 1. Blind | Check provider dashboard monthly. No per-request tracking. | None | Baseline |
| 2. Metered | Log tokens per request. Count tokens before sending. Know cost per feature. | Invisible Spend | 0% (visibility only) |
| 3. Optimized | Prompt caching, model routing, output constraints, batch APIs. | Cache Miss, Model Mismatch, Output Explosion | 40-70% |
| 4. Governed | Per-request limits, session budgets, daily caps, circuit breakers, alerting. | Runaway Agent, Context Bloat | 70-85% |
| 5. Autonomous | ML-based router selects model per request. Cost-quality tradeoff is automatic. | All | 85-95% |

Most teams operate at Level 1 or 2. The jump from Level 2 to Level 3 delivers the largest cost reduction for the least effort.

---

## Design Principles

### Principle 1: Count Tokens Before You Send Them

**Why it works:** You cannot manage what you do not measure. Token counting before API submission is the foundation of every other cost control -- it enables budget enforcement, anomaly detection, and cost prediction.

**How to apply:**

For OpenAI models, use `tiktoken`:

```python
import tiktoken

def estimate_cost(prompt: str, model: str = "gpt-5.6-sol") -> dict:
    enc = tiktoken.encoding_for_model(model)
    input_tokens = len(enc.encode(prompt))
    # Estimate output as 2x input for conversational, 0.5x for extraction
    estimated_output = input_tokens * 2

    prices = {"gpt-5.6-sol": (4.00, 20.00), "gpt-5.6-luna": (0.20, 1.20)}
    input_price, output_price = prices[model]

    cost = (input_tokens * input_price + estimated_output * output_price) / 1_000_000
    return {"input_tokens": input_tokens, "estimated_output": estimated_output,
            "estimated_cost_usd": cost}
```

For Anthropic models, use their token counting API endpoint or `anthropic.count_tokens()` in the SDK. Anthropic's tokenizer is not publicly available as a standalone library, so server-side counting is the only accurate method.

**Critical insight:** Token counting is not just for billing -- it is your first line of defense against context bloat and runaway costs. If a request's input token count exceeds your expected range, reject it before it reaches the API.

### Principle 2: Route by Complexity, Not by Default

**Why it works:** The router pattern, as documented in [AI-Native Solution Patterns](docs/ai-native-solution-patterns.md), uses an initial classification step to direct inputs to specialized handlers. When applied as a cost lever, a single routing decision -- "is this task simple or complex?" -- can cut costs by 50-70%. The cost differential between model tiers is not marginal: it is 10-50x.

| Tier | Models | Input / MTok | Output / MTok | Use For |
|---|---|---|---|---|
| Nano | GPT-5.6 Luna, Gemini 3.5 Flash-Lite | $0.20-$0.30 | $1.20-$2.50 | Classification, extraction, simple Q&A |
| Fast | Claude Haiku 4.5, Gemini 3.8 Flash, GPT-5.4 mini | $0.75-$1.00 | $3.75-$5.00 | Moderate reasoning, summarization |
| Standard | Claude Sonnet 5, GPT-5.6 Terra, Gemini 3.1 Pro | $2.00 | $10.00-$12.00 | Complex reasoning, generation |
| Frontier | GPT-5.6 Sol, Claude Opus 5 | $4.00-$5.00 | $20.00-$25.00 | Hardest tasks, multi-step reasoning |
| Above frontier | Claude Fable 5.1, GPT-6 Astra | $10.00 | $50.00 | Only where a measured quality gap justifies 2.5x the frontier rate |

**How to apply:**

```python
async def route_request(query: str) -> str:
    # Step 1: Classify complexity with cheapest model
    complexity = await classify(query, model="gpt-5.6-luna")  # $0.20/MTok

    # Step 2: Route to appropriate tier
    model_map = {
        "simple": "gpt-5.6-luna",        # FAQ, classification
        "moderate": "claude-haiku-4.5",  # Summarization, extraction
        "complex": "claude-sonnet-5",    # Analysis, generation
        "frontier": "claude-opus-5",     # Novel reasoning
    }
    return await generate(query, model=model_map[complexity])
```

Two refinements matter more than the routing table itself. Route on a **quality floor**, not on price: a cost-only router selects rate-limited free models and stalls under load, so rank by a quality score with the price cap as the guardrail underneath ([OpenRouter](https://openrouter.ai/docs/features/model-routing)). And check which direction an automatic router optimizes -- one that returns the *weakest* qualifying model is cost-first, not quality-first.

A system processing 50,000 requests/month with 70% simple, 20% moderate, and 10% complex tasks costs approximately $12,000/month with a single frontier model. With routing, it costs approximately $3,200/month -- a 73% reduction ([RocketEdge](https://rocketedge.com/2026/03/15/your-ai-agent-bill-is-30x-higher-than-it-needs-to-be-the-6-tier-fix/)). Published routing results support the same order of magnitude: a learned router reached more than 85% cost reduction on MT-Bench while keeping 95% of a frontier model's quality, by sending only 14% of queries to the strong model ([RouteLLM, ICLR 2025](https://arxiv.org/abs/2406.18665)).

### Principle 3: Cache at Multiple Layers

**Why it works:** Caching addresses the Cache Miss failure mode directly. Three caching strategies operate at different layers, and they stack.

**Layer 1: Exact-match response caching.** Hash the full prompt. If an identical prompt was seen recently, return the cached response. Hit rates are low (5-15%) but implementation cost is near zero.

**Layer 2: Semantic caching.** Embed the query, search for semantically similar prior queries (cosine similarity > 0.95), return the cached response. Hit rates reach 20-35% in enterprise workloads. Latency drops from ~850ms to ~120ms on cache hits ([Redis](https://redis.io/blog/llm-token-optimization-speed-up-apps/)).

**Layer 3: Provider prompt caching.** Anthropic and OpenAI cache repeated prompt prefixes server-side.

| Provider | Cache Write Cost | Cache Read Cost | Savings on Read | TTL |
|---|---|---|---|---|
| Anthropic (5-min) | 1.25x base input | 0.1x base input | 90% | 5 min (extends on access) |
| Anthropic (1-hour) | 2.0x base input | 0.1x base input | 90% | 1 hour |
| OpenAI (current flagship tiers) | 1.0x (free, automatic above 1,024 tokens) | 0.1x base input | 90% | 5-10 min |
| OpenAI (older models) | 1.0x (free) | 0.5x base input | 50% | 5-10 min |
| Google | Varies by model | ~0.1x base input | ~90% | Configurable |

*Source: [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing), [BenchLM cached-input column, 18 September 2026](https://benchlm.ai/llm-pricing), [Introl caching guide](https://introl.com/blog/prompt-caching-infrastructure-llm-cost-latency-reduction-guide-2025)*

The OpenAI row is the one teams get wrong: the discount is not uniform within one provider's catalogue. Read the cached-input column of the current price list, not the caching documentation, which lags the price change.

**Break-even analysis for Anthropic prompt caching:** A 5-minute cache write costs 1.25x one request. Cache reads cost 0.1x. Break-even occurs after **just 1 cache read** within the TTL window: 1.25x (write) + 0.1x (read) = 1.35x total for 2 requests, versus 2.0x without caching. Every subsequent read within the window saves 0.9x.

**How to apply:** Start with prompt caching (highest ROI, zero infrastructure). Add exact-match caching for high-repetition workloads. Graduate to semantic caching only if your query distribution shows high semantic overlap.

### Principle 4: Use Batch APIs for Non-Latency-Sensitive Work

**Why it works:** Both OpenAI and Anthropic offer **50% cost reduction** on batch API calls in exchange for a 24-hour completion window. If the work does not need a real-time response, you are overpaying by 2x.

**Workloads that fit batch processing:**
- Nightly evaluation runs against test datasets
- Bulk data enrichment and classification
- Content generation for scheduled publishing
- Document summarization backlogs
- Embedding generation for search indices

**How to apply:** Separate your workloads into "interactive" (user-facing, latency-sensitive) and "batch" (background, throughput-sensitive). Route batch workloads to the batch API. On a $10,000/month spend where 40% is batch-eligible, this saves $2,000/month with no quality impact.

### Principle 5: Set Hard Limits at Every Level

**Why it works:** This directly addresses the Runaway Agent failure mode. Without hard limits, a single malfunction can consume your entire monthly budget in hours. Guardrails must be structural (enforced by infrastructure), not behavioral (enforced by the model).

**How to apply -- four-level budget hierarchy:**

```
Organization     →  $50,000/month hard cap
  └─ Team        →  $10,000/month per team
      └─ API Key →  $500/day per key
          └─ Request → $1.00 per request, 4,096 max output tokens
```

**Agent-specific guardrails:**
- **Step limit:** No agent executes more than 25 tool calls per task
- **Session budget:** No single session exceeds $5.00
- **Time limit:** No agent runs longer than 10 minutes
- **Circuit breaker:** If any session exceeds $1.00 within 60 seconds, kill it

```python
class AgentBudget:
    def __init__(self, max_steps=25, max_cost_usd=5.0, max_duration_sec=600):
        self.max_steps = max_steps
        self.max_cost_usd = max_cost_usd
        self.max_duration_sec = max_duration_sec
        self.steps = 0
        self.cost = 0.0
        self.start_time = time.time()

    def check(self, step_cost: float) -> bool:
        self.steps += 1
        self.cost += step_cost
        elapsed = time.time() - self.start_time

        if self.steps > self.max_steps:
            raise BudgetExceeded(f"Step limit: {self.steps}/{self.max_steps}")
        if self.cost > self.max_cost_usd:
            raise BudgetExceeded(f"Cost limit: ${self.cost:.2f}/${self.max_cost_usd}")
        if elapsed > self.max_duration_sec:
            raise BudgetExceeded(f"Time limit: {elapsed:.0f}s/{self.max_duration_sec}s")
        return True
```

**Progressive alerting thresholds** ([Portkey](https://portkey.ai/blog/budget-limits-and-alerts-in-llm-apps/)):
- 50% budget consumed: notify team lead
- 75% budget consumed: notify engineering
- 90% budget consumed: switch to cheaper models automatically
- 100% budget consumed: block non-critical requests

### Principle 6: Track Cost Per Outcome, Not Cost Per Request

**Why it works:** Cost per request is a vanity metric. The metric that matters is **cost per successful outcome** -- the total cost to produce one unit of business value. An agent that costs $2.00 per request but resolves customer tickets autonomously (saving $15 in human labor) is cheaper than a $0.05 classifier that still requires human review.

**How to apply -- the metrics that matter:**

| Metric | What It Tells You | Alert Threshold |
|---|---|---|
| Cost per request | Raw API spend | Sudden 3x spike |
| Cost per successful outcome | Business unit economics | Exceeds value delivered |
| Cost per user | Distribution and abuse detection | Single user > 10x median |
| Cost per feature | Where budget goes | One feature > 40% of total |
| Token efficiency | Output quality per token | Declining over time |
| Cache hit rate | Caching effectiveness | Below 20% for eligible workloads |
| Cost trend (7-day rolling) | Trajectory | Week-over-week increase > 15% |

**Tool stack for monitoring:**

| Tool | Role | Integration |
|---|---|---|
| [LiteLLM](https://github.com/BerriAI/litellm) | API gateway, unified proxy | Routes to 100+ providers, enforces per-team budgets |
| [OpenRouter](https://openrouter.ai/docs/features/model-routing) | Routing and per-call price ceiling | Quality-ranked routing with a hard `max_price` guardrail and per-key monthly spend limits |
| [Langfuse](https://langfuse.com) | Observability and tracing | Cost breakdown by feature/team/model, trace visualization. Now developed inside ClickHouse, with the MIT core and self-hosting unchanged |
| [Portkey](https://portkey.ai) | AI gateway | Built-in caching, budget hierarchy, webhook alerts |
| [Helicone](https://helicone.ai) | Monitoring | One-line integration, prompt management, cost dashboards |

### Principle 7: Model the Full Cost Before You Build

**Why it works:** Most cost surprises come from not modeling costs during architecture design. A back-of-envelope calculation before writing code prevents 90% of budget overruns.

**How to apply -- cost estimation worksheet:**

```
SYSTEM: Customer support automation
VOLUME: 50,000 queries/month

Per-query breakdown:
  Router call (classify):     500 input + 50 output tokens
  RAG retrieval context:      2,000 input tokens
  Response generation:        2,000 input + 500 output tokens
  Quality check:              2,500 input + 100 output tokens
  ─────────────────────────────────────────────────
  Total per query:            7,000 input + 650 output tokens

Monthly tokens:
  Input:  7,000 × 50,000 = 350M tokens
  Output: 650 × 50,000   = 32.5M tokens

Cost at Claude Sonnet 5 ($2/$10 per MTok):
  Input:  350 × $2.00  = $700.00
  Output: 32.5 × $10.00 = $325.00
  Monthly total: $1,025.00

Cost with routing (70% to Haiku 4.5 at $1/$5):
  Simple (35K queries):  245M in × $1 + 22.75M out × $5  = $358.75
  Complex (15K queries): 105M in × $2 + 9.75M out × $10  = $307.50
  Monthly total: $666.25  (35% savings)

Cost with routing + prompt caching (60% cache hit on RAG context):
  Cached tokens: 2,000 × 30,000 hits = 60M tokens read at 10% of $2.00
  Additional monthly savings: ~$108
  Monthly total: ~$558.00  (46% savings from baseline)
```

---

## Evaluation: Real-World Systems

Four cost archetypes cover almost every LLM system in production. The tables below use September 2026 prices, recomputed from the same token volumes, so the *relative* savings are the part that transfers between price lists.

| Archetype | Dominant cost driver | Typical stack | Unoptimized | Optimized | Savings |
|---|---|---|---|---|---|
| Chatbot | Context accumulation across turns | Claude Sonnet 5, sliding window, Haiku 4.5 for simple turns | ~$2,530/mo | ~$800/mo | 68% |
| RAG pipeline | Repeated context injection | GPT-5.6 Terra, prompt caching, batch API for analytics | ~$1,700/mo | ~$740/mo | 57% |
| Agentic workflow | Unbounded step count | Sonnet 5, step limits, router, context pruning | ~$10,000/mo | ~$3,300/mo | 67% |
| Evaluation pipeline | High-volume, fully batch-eligible | Sonnet 5, batch API | ~$300/mo | ~$150/mo | 50% |

### Archetype 1: The Chatbot

Single-model, multi-turn conversation. Cost grows quadratically with conversation length due to context accumulation.

| Parameter | Value |
|---|---|
| Model | Sonnet 5 ($2/$10) |
| System prompt | 2,000 tokens |
| Avg turns per session | 15 |
| Avg user message | 100 tokens |
| Avg response | 300 tokens |
| Sessions per month | 10,000 |

**Unoptimized cost:** Each turn resends full history. By turn 15, input reaches ~8,000 tokens per request. Total monthly: ~$2,530.

**Optimized cost (sliding window + Haiku for simple turns):** Monthly: ~$800. **Savings: 68%.**

### Archetype 2: The RAG Pipeline

Retrieval-augmented generation with fixed document context. Cost dominated by repeated context injection.

| Parameter | Value |
|---|---|
| Model | GPT-5.6 Terra ($2/$12) |
| Retrieved context | 4,000 tokens |
| Query + system prompt | 1,500 tokens |
| Response | 500 tokens |
| Queries per month | 100,000 |

**Unoptimized cost:** 5,500 input + 500 output per query. Monthly: $1,700.

**Optimized cost (prompt caching + batch for analytics queries):** Monthly: ~$740. **Savings: 57%.**

### Archetype 3: The Agentic Workflow

Multi-step agent with tool calling. Cost is unpredictable because step count varies.

| Parameter | Value |
|---|---|
| Model | Sonnet 5 ($2/$10) |
| Steps per task | 5-25 (avg 12) |
| Tokens per step | 3,000 input + 500 output (growing with context) |
| Tasks per month | 5,000 |

**Unoptimized cost:** Average 12 steps, context grows each step. Monthly: ~$10,000. **Worst case (all tasks hit 25 steps):** ~$30,000.

**Optimized cost (step limits + router + context pruning):** Monthly: ~$3,300. **Savings: 67%. Risk reduction: 90% (worst case capped at ~$5,300).**

This is where the published measurements are starkest: agentic workloads consume 5-30x more tokens per task than a chatbot exchange, and coding agents on a software-engineering benchmark used up to 1,000x the tokens of simple code chat, driven almost entirely by re-read input ([Spheron](https://www.spheron.network/blog/agentic-ai-inference-cost-2026)).

### Archetype 4: The Evaluation Pipeline

Batch evaluation of model outputs using LLM-as-judge. High volume, fully batch-eligible.

| Parameter | Value |
|---|---|
| Model | Sonnet 5 ($2/$10) |
| Items to evaluate | 50,000/month |
| Tokens per evaluation | 2,000 input + 200 output |

**Unoptimized cost (real-time API):** Monthly: $300.

**Optimized cost (batch API at 50% discount):** Monthly: $150. **Savings: 50%, zero effort.**

---

## The Build-vs-Buy Decision: When Self-Hosting Makes Sense

The instinct to self-host for cost savings is almost always premature. The true cost of self-hosting is consistently [underestimated by 2-3x](https://devtk.ai/en/blog/self-hosting-llm-vs-api-cost-2026/).

**True cost of self-hosting (monthly, single A100 80GB):**

| Component | Cost |
|---|---|
| GPU rental (A100 80GB, cloud) | $1,440 |
| DevOps engineering (15 hrs × $100/hr) | $1,500 |
| Infrastructure (monitoring, load balancing) | $300 |
| **True monthly total** | **$3,240** |

**Break-even volumes against APIs:**

| Compare Against | Break-Even Volume | Reality Check |
|---|---|---|
| Claude Sonnet 5 ($2/$10) | ~75M tokens/month | Achievable for high-volume systems |
| GPT-5.6 Luna ($0.20/$1.20) | ~1.4B tokens/month | Nearly impossible on single GPU |
| Gemini 3.5 Flash-Lite ($0.30/$2.50) | ~0.7B tokens/month | Requires maximum 24/7 utilization |

*Break-even volumes recomputed at September 2026 prices against the same $3,240/month self-host total.*

An [academic study of 54 deployment scenarios](https://arxiv.org/html/2509.18101v1) found that small models (24-32B parameters) break even in 0.3-3 months on consumer hardware (~$2,000), while large models (235B+) require 3.5-69+ months on $60K-$240K hardware. Against cost-leadership APIs, payoff horizons extend to 5-9 years.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#e8f4f8', 'primaryTextColor': '#1a1a2e', 'primaryBorderColor': '#5b8a9a', 'lineColor': '#5b8a9a', 'secondaryColor': '#f0e6d3', 'tertiaryColor': '#e8e8e8', 'clusterBkg': '#f5f5f5', 'edgeLabelBackground': '#f5f5f5'}}}%%
quadrantChart
    title Self-Host vs API Decision
    x-axis Low Volume --> High Volume
    y-axis Budget Models --> Frontier Models
    quadrant-1 Self-host likely wins
    quadrant-2 API wins (frontier quality needed)
    quadrant-3 API wins (low volume)
    quadrant-4 Evaluate carefully
    API chatbot: [0.3, 0.7]
    API RAG: [0.4, 0.5]
    Self-host classification: [0.8, 0.2]
    Self-host embeddings: [0.9, 0.15]
    Agentic workflow: [0.5, 0.85]
    Batch enrichment: [0.75, 0.3]
```

**Self-host when:** You process 100M+ tokens/day consistently, need data residency or air-gapped deployment, require custom fine-tuned models, or have a dedicated ML infrastructure team.

**Use APIs when:** Volume is below 50M tokens/day, you need frontier-model quality, your team lacks GPU operations expertise, or traffic is variable/spiky.

---

## Field Notes from an Operating Estate

- **September 2026 -- the money brake was dead and every part of it looked correct.** An unattended nightly batch job had an in-run spend stop-condition: read the provider's usage figure, subtract the value recorded at run start, stop when the delta reached the night's allowance. It was wired, configured, and reported in every run summary. On the measured run, the windowed usage figure fell by 149.89 during the job while the money actually spent -- read from the remaining-credit field on the *same* API response -- was 0.109. The delta was therefore negative from the first re-read and could never reach the allowance. The brake had never fired, and the only working control was the pre-run arithmetic that decides once, at the start. Two fields on one payload disagreed about which one carried the spend. The fix was to brake on the remaining-credit field, which only falls, and to treat "is this counter monotonic inside the accounting period?" as a required review question for every budget check.

- **July 2026 -- a per-token price cap did not bound the bill.** An operator set a hard per-token price ceiling on a routing layer, expecting it to bound spending. It bounds the *rate* per token, not dollars per call: a long-enough answer at an allowed rate is still an expensive call, and an output-token bound is required alongside the price cap. A second surprise followed: a cap set to a model's cheapest *listed* endpoint failed outright, because the router did not serve from that endpoint. The meter you read must be the endpoint that is actually served.

- **July 2026 -- a cost-only router selected the free tier and stalled.** With a low price ceiling in place, $0/$0 models satisfy the cap by definition, and a price-sorted router preferred them. Under load the free models were rate-limited, so the routing layer stalled rather than spending. The fix was to route on a quality floor -- a minimum score -- with the price cap kept as the guardrail underneath, rather than sorting by price. Cost-first routing and quality-first routing produce the same bill on paper and very different systems in practice.

## Recommendations

### Short-Term (This Week)

1. **Instrument token counting on every request.** Log input tokens, output tokens, model, and cost per call. You cannot optimize what you cannot see. (Implements Principle 1)
2. **Set `max_tokens` on every API call.** Prevents output explosions. Match the limit to the expected response format -- 200 for JSON extraction, 1,000 for summaries, 4,096 for generation. (Implements Principle 5)
3. **Enable prompt caching.** If using Anthropic, add `cache_control` markers to system prompts and repeated context. If using OpenAI, prompts over 1,024 tokens cache automatically. Zero infrastructure required. (Implements Principle 3)
4. **Switch batch-eligible workloads to batch APIs.** Evaluations, enrichment, and scheduled generation get 50% off immediately. (Implements Principle 4)

### Medium-Term (This Month)

5. **Implement model routing.** Classify request complexity and route to the cheapest model that meets quality requirements. Start with a simple rule-based router before investing in ML-based classification. (Implements Principle 2)
6. **Add budget guardrails.** Per-request cost limits, per-session budgets, daily caps, and progressive alerting. Every agent must have a step limit and a cost ceiling. (Implements Principle 5)
7. **Build cost attribution.** Tag every request with feature, user, and team. Build a dashboard showing cost per outcome, not just cost per request. (Implements Principle 6)

### Long-Term (This Quarter)

8. **Implement semantic caching.** For workloads with high query similarity, add embedding-based cache lookup. Target 20-35% hit rates. (Implements Principle 3)
9. **Automate cost-quality optimization.** Build evaluation harnesses that measure quality at each model tier. Continuously optimize the routing threshold as models improve and prices drop. (Implements Principle 2)
10. **Run cost modeling for every new feature.** Before any new LLM feature ships, complete the cost estimation worksheet from Principle 7. Make it part of the design review. (Implements Principle 7)

---

## The Hard Truth

The LLM cost problem is not a pricing problem. Prices have dropped approximately [100x over 2.5 years](https://simonwillison.net/tags/llm-pricing/) and will continue dropping. The problem is architectural.

Falling prices are also a trap, and this is the 2026 version of the same mistake. Per-token prices keep falling while agentic workloads consume 5-30x more tokens per task than a chat exchange, and a study of coding agents on a software-engineering benchmark reported agents using up to 1,000x the tokens of simple code chat on the same benchmark, driven almost entirely by re-read input ([Gartner, March 2026](https://www.gartner.com/en/newsroom/press-releases/2026-03-25-gartner-predicts-that-by-2030-performing-inference-on-an-llm-with-1-trillion-parameters-will-cost-genai-providers-over-90-percent-less-than-in-2025), [Spheron](https://www.spheron.network/blog/agentic-ai-inference-cost-2026)). A 10x price cut and a 30x volume increase still raises the bill. Gartner's August 2026 forecast agrees from the other direction: inference cost per agentic workflow is expected to increase more than fivefold through 2028, and no economical one-size-fits-all model is on the horizon ([Gartner, August 2026](https://www.gartner.com/en/newsroom/press-releases/2026-08-17-gartner-predicts-ai-inference-costs-per-agentic-workflow-will-increase-more-than-fivefold-through-2028)).

Teams that treat LLM calls like database queries -- fire and forget, optimize later -- will always be surprised by their bills. The cost of a single LLM call is trivial. The cost of a system that makes thousands of uncontrolled LLM calls is catastrophic. The difference between a $500/month system and a $50,000/month system is rarely the model or the provider. It is whether anyone modeled the cost before building, whether anyone set limits before deploying, and whether anyone monitored before the invoice arrived.

The uncomfortable truth is that 96% of enterprises report AI costs exceeding estimates ([OneUptime](https://oneuptime.com/blog/post/2026-03-09-ai-agents-observability-crisis/view)). This is not because LLMs are expensive. It is because teams build first and budget never. A 30-minute cost estimation exercise before architecture design prevents more financial damage than any optimization applied after the fact.

The most expensive LLM system is the one nobody measured.

---

## Summary Checklist

| Question | Good Answer | Bad Answer |
|---|---|---|
| Do you count tokens before sending requests? | Yes, with alerts on anomalies | No, we check the monthly bill |
| Do you use different models for different complexity levels? | Yes, 3+ tiers with routing | No, one model for everything |
| Do you cache repeated prompt prefixes? | Yes, with measured hit rates | No, or we have not checked |
| Are agent loops bounded by step and cost limits? | Yes, hard limits with circuit breakers | No, agents run until done |
| Do you know cost per successful outcome? | Yes, tracked per feature | No, only aggregate spend |
| Is batch API used for non-real-time work? | Yes, all eligible workloads | No, everything is real-time |
| Did you model costs before building? | Yes, cost worksheet in design review | No, we estimated after launch |
| Do you have a kill switch for runaway sessions? | Yes, automatic circuit breaker | No, we rely on manual intervention |

---

## References

### Practitioner Articles

- [TechStartups: AI Agents Horror Stories -- $47,000 Failure](https://techstartups.com/2025/11/14/ai-agents-horror-stories-how-a-47000-failure-exposed-the-hype-and-hidden-risks-of-multi-agent-systems/) -- Detailed case study of an 11-day agent loop costing $47,000, with root cause analysis
- [RocketEdge: Your AI Agent Bill Is 30x Higher Than It Needs to Be](https://rocketedge.com/2026/03/15/your-ai-agent-bill-is-30x-higher-than-it-needs-to-be-the-6-tier-fix/) -- Six-tier model routing framework achieving 97.8% cost reduction with circuit-breaker patterns
- [Pluralsight: Meter Before You Manage -- How to Cut LLM Costs](https://www.pluralsight.com/resources/blog/ai-and-data/how-cut-llm-costs-with-metering) -- Three-layer methodology (LiteLLM + Langfuse + RouteLLM) reducing a $47K monthly bill to $28K
- [Moltbook-AI: AI Agent Cost Optimization 2026](https://moltbook-ai.com/posts/ai-agent-cost-optimization-2026) -- Ten optimization strategies with specific savings percentages and monthly cost comparisons
- [Koombea: LLM Cost Optimization Guide](https://ai.koombea.com/blog/llm-cost-optimization) -- Model cascading achieving 87% savings, LLMLingua compression details, and self-hosting payback calculations
- [Simon Willison: LLM Pricing](https://simonwillison.net/tags/llm-pricing/) -- Running archive documenting 100x price reductions over 2.5 years across all major providers

### Official Documentation and Pricing

- [Anthropic Pricing](https://platform.claude.com/docs/en/about-claude/pricing) -- Authoritative source for Claude model pricing, prompt caching multipliers, batch discounts, and tool pricing
- [OpenAI API Pricing Guide 2026](https://devtk.ai/en/blog/openai-api-pricing-guide-2026/) -- Complete pricing table including GPT-5, GPT-4.1 family, o3, and o4-mini with batch and caching discounts
- [Google AI Pricing](https://ai.google.dev/pricing) -- Complete Gemini model lineup including free tiers and context caching costs
- [Finout: OpenAI vs Anthropic API Pricing Comparison](https://www.finout.io/blog/openai-vs-anthropic-api-pricing-comparison) -- Side-by-side comparison with batch and caching discount breakdowns

### Technical Guides

- [Redis: LLM Token Optimization -- Cut Costs and Latency](https://redis.io/blog/llm-token-optimization-speed-up-apps/) -- Semantic caching architecture, multi-tier caching strategy, and real-world cost comparisons showing 16x differences between model tiers
- [Introl: Prompt Caching Infrastructure Guide](https://introl.com/blog/prompt-caching-infrastructure-llm-cost-latency-reduction-guide-2025) -- Provider-specific caching implementations with break-even calculations and ROI formulas
- [Portkey: AI Cost Observability Guide](https://portkey.ai/blog/ai-cost-observability-a-practical-guide-to-understanding-and-managing-llm-spend/) -- Five pillars of cost observability with FinOps integration approach
- [Portkey: Budget Limits and Alerts in LLM Apps](https://portkey.ai/blog/budget-limits-and-alerts-in-llm-apps/) -- Progressive alerting thresholds and centralized gateway architecture

### Monitoring and Operations

- [Helicone: Monitor and Optimize LLM Costs](https://www.helicone.ai/blog/monitor-and-optimize-llm-costs) -- Per-request cost benchmarks across workload types and 30-50% savings from prompt optimization plus caching
- [OneUptime: AI Agents Running Blind](https://oneuptime.com/blog/post/2026-03-09-ai-agents-observability-crisis/view) -- Agent observability failures, fintech database incident, and decision-level instrumentation recommendations
- [Finout: FinOps in the Age of AI](https://www.finout.io/blog/finops-in-the-age-of-ai-a-cpos-guide-to-llm-workflows-rag-ai-agents-and-agentic-systems) -- Tagging and allocation strategies, chargeback models, and 30x-200x cost variance between optimized and unoptimized deployments

### Research

- [Self-Hosting LLM vs API Cost Analysis 2026](https://devtk.ai/en/blog/self-hosting-llm-vs-api-cost-2026/) -- GPU pricing tables, break-even calculations against four API providers, and hidden cost multipliers
- [arxiv 2509.18101: Cost-Benefit Analysis of On-Premise LLM Deployment](https://arxiv.org/html/2509.18101v1) -- Academic analysis of 54 deployment scenarios with break-even timelines by model size across three commercial pricing tiers
- [Latent Space: Simon Willison -- Things We Learned About LLMs in 2024](https://www.latent.space/p/2024-simonw) -- Key insight: Gemini 1.5 Flash processes 68,000 photos for $1.68; DeepSeek v3 trained for $5.5M (1/10th expected)

### September 2026 Pricing, Routing and Consumption

- [BenchLM: LLM API Pricing Comparison](https://benchlm.ai/llm-pricing) -- Dated price table across 157 paid models and 28 providers, with a cached-input column; the primary source for the price table above (verified 18 September 2026)
- [OpenAI API Pricing](https://openai.com/api/pricing/) -- Current model line-up, batch discount and cached-input rates
- [Google AI Pricing](https://ai.google.dev/pricing) -- Gemini model line-up and context-caching costs
- [Gartner: Agentic AI token consumption, March 2026](https://www.gartner.com/en/newsroom/press-releases/2026-03-25-gartner-predicts-that-by-2030-performing-inference-on-an-llm-with-1-trillion-parameters-will-cost-genai-providers-over-90-percent-less-than-in-2025) -- Source of the 5-30x token-per-task multiplier for agentic workloads against a standard chatbot exchange
- [Gartner: inference cost per agentic workflow, August 2026](https://www.gartner.com/en/newsroom/press-releases/2026-08-17-gartner-predicts-ai-inference-costs-per-agentic-workflow-will-increase-more-than-fivefold-through-2028) -- Forecast that inference cost per agentic workflow increases more than fivefold through 2028, and the argument against a single-model strategy
- [Spheron: Agentic AI Inference Cost](https://www.spheron.network/blog/agentic-ai-inference-cost-2026) -- Collects the measured multipliers, including the coding-agent finding of up to 1,000x tokens against simple code chat
- [RouteLLM: Learning to Route LLMs with Preference Data](https://arxiv.org/abs/2406.18665) -- Learned routing reaching over 85% cost reduction at 95% of frontier-model quality, with only 14% of queries sent to the strong model
- [OpenRouter: Model Routing](https://openrouter.ai/docs/features/model-routing) -- Quality-ranked routing under a hard per-call price ceiling, and per-key monthly spend limits

### Related Documents in This Series

- [AI-Native Solution Patterns](docs/ai-native-solution-patterns.md) -- The router pattern as an architectural cost lever; seven patterns ordered by increasing complexity and cost
- [LLM Fundamentals for Practitioners](docs/llm-fundamentals-for-practitioners.md) -- Token mechanics, model tier pricing, and the 50-70% savings from a single routing decision

---

*Last reviewed: September 2026. Changed in this revision: every price, model name and cached-input rate corrected against September 2026 price lists (the March 2026 table listed GPT-4.1, GPT-5, o3, Sonnet 4.6, Opus 4.6 and Gemini 2.5 as current); OpenAI's cached-input discount corrected from a flat 50% to 90% on current flagship tiers; added Failure 7 (the dead brake), the 2026 agentic token-consumption measurements, and field notes from an operating estate.*
