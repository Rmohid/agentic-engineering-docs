# Agentic Engineering: A Practitioner's Guide

From "what is a token" to production multi-agent systems -- 20 deep-dives that build on each other in sequence, plus companion references.

This documentation suite is designed for engineers who need to build production systems that leverage AI. It assumes programming experience but no prior LLM knowledge. Each document is self-contained but designed to be read in order -- later documents reference concepts and patterns introduced in earlier ones.

---

## How to Use This Guide

**If you are new to LLMs:** Start at Tier 1 and read sequentially. Each document builds directly on the previous one.

**If you can already call an LLM API and write prompts:** Skip to Tier 2. Skim Tier 1 documents for any gaps in your mental model.

**If you are already building agentic systems:** Start at Tier 3. The evaluation, security, and operational documents address the problems that surface in production.

**If you need to solve a specific problem now:** Use the problem-pattern index at the bottom of this page to find the right document.

---

## Tier 1: Foundations

*What LLMs are, how to use them, and the three skills every LLM application depends on.*

Read this tier if you have never built anything with an LLM, or if your experience is limited to ChatGPT-style conversations. After completing Tier 1, you will be able to build single-call LLM applications that produce structured, reliable output.

### 1. [LLM Fundamentals for Practitioners](llm-fundamentals-for-practitioners.md)

**You need this if:** You have never called an LLM API, or you use LLMs but do not understand tokens, context windows, or why temperature matters.

What tokens are and why they determine cost and context limits. How next-token prediction explains hallucination. The anatomy of an API call. How to choose between model tiers. The practical differences between providers. Concrete Python code for your first API calls.

**After reading:** You understand the machine well enough to reason about its behavior.

### 2. [Prompt Engineering That Works](prompt-engineering.md)

**You need this if:** You write prompts by trial and error, or your prompts work on test inputs but fail on production traffic.

System prompts that constrain behavior. Few-shot examples: when they help, when they waste tokens. Chain-of-thought: when it improves accuracy, when it hurts. Output format instructions that work. Prompt versioning as engineering practice.

**After reading:** You can write prompts that produce consistent, high-quality output for well-defined tasks.

### 3. [Context Engineering](context-engineering.md)

**You need this if:** You have hit context window limits, or your system's output quality degrades as conversations get longer.

The context window as a budget. Information placement and the lost-in-the-middle problem. Context compression techniques. Conversation history management. Sub-agents as context management tools. Why more context is not always better.

**After reading:** You can architect what goes into the context window and manage it across multi-step interactions.

### 4. [Structured Output and Output Parsing](structured-output-and-parsing.md)

**You need this if:** Your LLM outputs are unpredictable text that downstream code cannot reliably parse.

JSON mode across providers. Function calling as a structured output mechanism. Pydantic models for type-safe extraction. Schema design for LLM output. Validation and retry strategies. The tradeoff between strict schemas and model flexibility.

**After reading:** You can make LLM output machine-readable and integrate it into software systems.

---

## Tier 2: Core Patterns

*The building blocks for real systems: retrieval, tools, pattern selection, and evaluation.*

Read this tier when you can write reliable single-call LLM applications and need to build something more complex. After completing Tier 2, you will be able to select the right architectural pattern for a given problem, build RAG pipelines and tool-using agents, and measure whether your system actually works.

### 5. [RAG: From Concept to Production](rag-from-concept-to-production.md)

**You need this if:** Your LLM needs access to information it was not trained on -- documents, databases, or real-time data.

The RAG pipeline architecture. Chunking strategies that matter. Embedding models and vector databases. Retrieval methods beyond naive similarity. Reranking. Citation and source attribution. Production ingestion pipelines. RAG-specific failure modes.

**After reading:** You can build a RAG pipeline that grounds LLM output in your data.

### 6. [Tool Design for LLM Agents](tool-design-for-llm-agents.md)

**You need this if:** You are building an agent that needs to take actions -- call APIs, query databases, execute code, or interact with external systems.

What tools are in the LLM context. The anatomy of a good tool definition. Function calling across providers. MCP (Model Context Protocol). Tool design principles. The tool selection problem. Sandboxing and permissions.

**After reading:** You can design tools that agents use reliably, and you understand MCP as the emerging integration standard.

### 7. [AI-Native Solution Patterns](ai-native-solution-patterns.md)

**You need this if:** You have a problem to solve and need to decide which architectural pattern to use -- single call, pipeline, router, agent, or multi-agent.

The pattern catalog: 7 patterns with build stages for each. The complexity escalation ladder. Problem-pattern matching. The knowledge enhancement track (RAG vs fine-tuning vs prompt engineering). Why most teams over-architect.

**After reading:** You can select the simplest pattern that solves your problem and build it stage by stage.

### 8. [Evaluation-Driven Development](evaluation-driven-development.md)

**You need this if:** You iterate on your LLM system by "testing a few inputs" and shipping when it "looks right."

The eval flywheel. Building golden datasets. Code-based, embedding-based, and LLM-as-judge evaluation. Statistical rigor. Evaluation frameworks (DeepEval, RAGAS, Braintrust, Promptfoo). Continuous production evaluation. Connecting eval scores to business metrics.

**After reading:** You can build the measurement infrastructure that tells you whether your system is actually improving.

### 9. [Fine-Tuning for Practitioners](fine-tuning-for-practitioners.md)

**You need this if:** Prompting cannot reliably produce the behavior you need at scale, and you need to decide whether fine-tuning is worth the investment.

When to fine-tune vs prompt engineering vs RAG -- the decision framework. SFT, DPO, and RLHF: what each method does and when to use it. LoRA as the production default. Data curation (quality over quantity). Distillation for cost reduction. Fine-tuning failure modes (catastrophic forgetting, template mismatch, overfitting). Current costs across providers.

**After reading:** You can make a disciplined decision about whether to fine-tune, and if so, execute the process without the common pitfalls.

---

## Tier 3: Quality and Safety

*How to make systems reliable, secure, and trustworthy in production.*

Read this tier when you have a working system and need to harden it for real users. These documents address the problems that surface when your system handles untrusted input, makes consequential decisions, or runs at scale.

### 10. [LLM Role Separation: Executor vs Evaluator](llm-role-separation-executor-evaluator.md)

**You need this if:** Your system uses the same LLM to both produce and judge its output, or you are building evaluation into your pipeline.

Why shared cognition corrupts judgment. 7 levels of isolation from same-call to hybrid cascade. Implementation patterns across frameworks (AutoGen, CrewAI, DSPy, DeepEval, RAGAS). The evaluation cascade for production cost optimization. Per-dimension isolated judges.

**After reading:** You can architect evaluation so that the judge is genuinely independent of the executor.

### 11. [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md)

**You need this if:** Your agents skip steps, rationalize bad output, or fail quality checks that look correct on paper.

Why self-enforcement fails when the LLM is both worker and inspector. 6 failure modes of quality gates. The gate reliability spectrum (Levels 0-5). Design principles for gates that actually hold. Evidence over claims. Structural enforcement over prompt-based constraints.

**After reading:** You can design quality gates that the LLM cannot rationalize around.

### 12. [Security and Safety in LLM Applications](security-and-safety.md)

**You need this if:** Your system handles user input, processes external data, or makes decisions that affect real people.

The LLM threat model. Direct and indirect prompt injection. The defense hierarchy. PII handling. Content filtering. Guardrail design. The six security patterns (IBM/ETH Zurich). Supply chain risks. Red teaming and security testing.

**After reading:** You understand the threats to your LLM system and can implement layered defenses.

---

## Tier 4: Production Operations

*The infrastructure that keeps systems running, affordable, and improving over time.*

Read this tier when you are moving from prototype to production, or when your production system has operational problems (cost overruns, silent quality degradation, context overflow, user trust issues).

### 13. [Memory and State Management](memory-and-state-management.md)

**You need this if:** Your agents forget context between turns, your long-running agents degrade as conversations grow, or you need persistence across sessions.

The memory taxonomy (working, short-term, long-term). Conversation memory strategies. Long-term memory architectures. The memory-context bridge. Checkpointing for long-running agents. Experience replay. Practical implementations with real tools.

**After reading:** You can build memory systems that give agents coherent, persistent state.

### 14. [Cost Engineering for LLM Systems](cost-engineering-for-llm-systems.md)

**You need this if:** Your LLM costs are unpredictable, growing, or preventing you from scaling.

The token cost model. Cost estimation per pattern. Caching strategies (exact, semantic, prompt caching). Model routing for cost. Batch APIs. Cost controls and guardrails. The runaway agent problem. Build-vs-buy for self-hosted models.

**After reading:** You can budget, monitor, and optimize the cost of your LLM system.

### 15. [Observability and Monitoring](observability-and-monitoring.md)

**You need this if:** You cannot explain why your LLM system produced a specific output, or you discover quality problems only when users complain.

Why LLM observability differs from traditional monitoring. What to log. Multi-step tracing. The observability stack (Langfuse, Helicone, Braintrust). Quality monitoring and drift detection. Debugging non-deterministic failures. Dashboards that matter.

**After reading:** You can see inside your LLM system and detect problems before users do.

### 16. [Human-in-the-Loop Patterns](human-in-the-loop-patterns.md)

**You need this if:** You need to decide how much autonomy to give your AI system, or you need human oversight without destroying the value of automation.

The four levels of human involvement. Approval workflow architecture. Escalation trigger design. The approval fatigue anti-pattern. Handoff protocols. Progressive autonomy. Audit trails for compliance.

**After reading:** You can design the boundary between human judgment and machine autonomy.

### 17. [Testing and Shipping LLM Systems](testing-and-shipping-llm-systems.md)

**You need this if:** You deploy prompt changes by editing a string and hoping for the best, or you have no CI/CD pipeline for your LLM components.

The three-layer testing architecture (deterministic unit tests, LLM evaluation tests, end-to-end scenario tests). Prompt versioning as engineering practice. CI/CD pipelines for LLM applications. Shadow, canary, and A/B deployment strategies. Rollback architecture. The data flywheel that turns production failures into regression tests.

**After reading:** You can deploy LLM changes with the same rigor as code changes -- versioned, tested, progressively rolled out, and instantly rollbackable.

### 18. [Reliability Engineering for LLM Applications](reliability-engineering-for-llm-applications.md)

**You need this if:** Your LLM-integrated system has no retry strategy, no fallback when providers fail, or no protection against runaway agents.

The three-tier retry strategy. Quality-aware circuit breakers. Multi-provider failover architectures. Adaptive timeouts for variable-latency LLM calls. Idempotent tool execution. Runaway agent prevention. Graceful degradation ladders. Chaos engineering for LLM systems.

**After reading:** You can keep your LLM system running when providers fail, models degrade, and agents misbehave.

---

## Tier 5: Advanced Architecture

*Patterns for systems that coordinate multiple agents or improve themselves over time. Read these last -- most production systems never need them.*

### 19. [Multi-Agent Coordination](multi-agent-coordination.md)

**You need this if:** You have proven that a single agent cannot handle your task, and simpler patterns (router, orchestrator-workers) are insufficient.

When multi-agent is warranted (less than 0.1% of use cases). Communication patterns. Orchestration models. Shared state management. The MapReduce pattern. Agent handoff protocols. Cost reality (5-10x single agents). Multi-agent failure modes. Framework comparison.

**After reading:** You can design multi-agent systems for the rare cases that genuinely need them, and you know when to avoid them.

### 20. [Self-Improving Systems](self-improving-systems.md)

**You need this if:** You want to build systems that improve their own performance through feedback loops, automated experimentation, or self-training.

Why most loops plateau. The evaluator independence principle. 6 failure modes of self-improvement. The self-improvement spectrum (static pipeline to recursive self-modification). Karpathy's autoresearch in detail. AlphaEvolve. Principles for sustained improvement.

**After reading:** You understand what actually drives sustained self-improvement and why most attempts fail after the first few cycles.

---

## Problem-Pattern Index

*Find the right document for your specific problem.*

| I need to... | Start here | Then read |
|---|---|---|
| Make my first LLM API call | [1. Fundamentals](llm-fundamentals-for-practitioners.md) | [2. Prompt Engineering](prompt-engineering.md) |
| Get consistent, parseable output | [4. Structured Output](structured-output-and-parsing.md) | [2. Prompt Engineering](prompt-engineering.md) |
| Give my LLM access to my data | [5. RAG](rag-from-concept-to-production.md) | [3. Context Engineering](context-engineering.md) |
| Build an agent that uses tools | [6. Tool Design](tool-design-for-llm-agents.md) | [7. Solution Patterns](ai-native-solution-patterns.md) |
| Decide which pattern to use | [7. Solution Patterns](ai-native-solution-patterns.md) | [8. Evaluation](evaluation-driven-development.md) |
| Measure if my system works | [8. Evaluation](evaluation-driven-development.md) | [10. Role Separation](llm-role-separation-executor-evaluator.md) |
| Fine-tune a model for my use case | [9. Fine-Tuning](fine-tuning-for-practitioners.md) | [8. Evaluation](evaluation-driven-development.md) |
| Prevent prompt injection | [12. Security](security-and-safety.md) | [11. Quality Gates](quality-gates-in-agentic-systems.md) |
| Control costs | [14. Cost Engineering](cost-engineering-for-llm-systems.md) | [7. Solution Patterns](ai-native-solution-patterns.md) |
| Debug production issues | [15. Observability](observability-and-monitoring.md) | [8. Evaluation](evaluation-driven-development.md) |
| Add human oversight | [16. Human-in-the-Loop](human-in-the-loop-patterns.md) | [11. Quality Gates](quality-gates-in-agentic-systems.md) |
| Ship prompt changes safely | [17. Testing and Shipping](testing-and-shipping-llm-systems.md) | [15. Observability](observability-and-monitoring.md) |
| Handle provider failures | [18. Reliability](reliability-engineering-for-llm-applications.md) | [14. Cost Engineering](cost-engineering-for-llm-systems.md) |
| Coordinate multiple agents | [19. Multi-Agent](multi-agent-coordination.md) | [13. Memory](memory-and-state-management.md) |
| Build self-improving loops | [20. Self-Improving](self-improving-systems.md) | [10. Role Separation](llm-role-separation-executor-evaluator.md) |
| Choose a framework or tool | [Framework Landscape](ai-native-framework-landscape.md) | [7. Solution Patterns](ai-native-solution-patterns.md) |

---

## Companion References

*Standalone reference documents that complement the main curriculum. Not part of the sequential reading order.*

### [The AI-Native Framework Landscape](ai-native-framework-landscape.md)

A comprehensive map of 22+ production-grade third-party frameworks across 7 layers of the AI application stack: inference/serving, vector storage, LLM gateways, structured output, orchestration, agent frameworks, and evaluation/observability. Includes composition patterns, a decision framework, and practitioner consensus on when to use (and skip) frameworks.

### [File-Based Memory for AI Systems](file-based-memory-for-ai-systems.md)

A practical pattern for implementing persistent memory in AI coding agents and assistants using the filesystem. Covers memory file structure, indexing strategies, and retrieval patterns for systems that need to remember context across sessions without external infrastructure.

---

## About This Suite

Every document follows the same structure: problem diagnosis before solutions, failure taxonomy before recommendations, concrete code before abstract advice. No document assumes you have read any other unless it is listed as a prerequisite.

The documents are opinionated. They reflect the current practitioner consensus (Anthropic, OpenAI, Google, and the broader engineering community) as of March 2026. Where sources disagree, the documents state the disagreement rather than picking a side.

The consistent message across all 20 documents: **start with the simplest approach that could work, measure whether it does, and escalate complexity only when the data demands it.**
