#!/usr/bin/env bash
#
# generate-deep-dives.sh
#
# Generates a comprehensive agentic engineering documentation suite
# by running /deep-dive prompts through Claude Code sequentially.
#
# This script produces all 17 deep-dives in the suite, including
# regeneration of previously-written docs to add inline citations
# and a References section for source verification.
#
# Usage:
#   chmod +x generate-deep-dives.sh
#   ./generate-deep-dives.sh
#
# To resume from a specific step (e.g., step 5):
#   RESUME_FROM=5 ./generate-deep-dives.sh
#
# Each deep-dive takes 3-8 minutes. Total: ~60-90 minutes.

set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/docs" && pwd)"
RESUME_FROM="${RESUME_FROM:-1}"
TOTAL=17

log() {
    echo ""
    echo "============================================================"
    echo "  [$1/$TOTAL] $2"
    echo "============================================================"
    echo ""
}

# Reads the prompt from stdin. This avoids the bash bug where
# $(cat <<'HEREDOC' ... HEREDOC) breaks on content containing
# unmatched parentheses.
run_deep_dive() {
    local step="$1"
    local prompt
    prompt="$(cat)"

    if [ "$step" -lt "$RESUME_FROM" ]; then
        echo "  Skipping step $step (resuming from $RESUME_FROM)"
        return 0
    fi

    claude --print -p "/deep-dive $prompt"

    echo ""
    echo "  Step $step complete."
    echo ""
}

echo ""
echo "Agentic Engineering Documentation Suite Generator"
echo "================================================="
echo "Output directory: $DOCS_DIR"
echo "Resuming from step: $RESUME_FROM"
echo "Total deep-dives: $TOTAL"
echo ""

# ---------------------------------------------------------------------------
# 1. LLM FUNDAMENTALS FOR PRACTITIONERS
# ---------------------------------------------------------------------------
log 1 "LLM Fundamentals for Practitioners"
run_deep_dive 1 <<'PROMPT'
LLM fundamentals for practitioners who need to build production systems, not researchers. Cover the practical mental model: what is a token and why token counts determine cost and context limits, what a context window is and why its size is the single most important constraint in system design, how next-token prediction works at a level that explains why LLMs hallucinate and why temperature/top-p matter, the anatomy of an API call -- system/user/assistant messages, chat completions, streaming --, how to choose between model tiers -- Haiku-class vs Sonnet-class vs Opus-class -- based on task complexity and cost, and the practical differences between providers -- OpenAI, Anthropic, Google. This is the on-ramp for the full documentation suite -- assume the reader has programmed before but has never called an LLM API. Emphasize what practitioners get wrong: confusing model size with capability for their task, ignoring context window limits until they hit them, not understanding that temperature=0 does not mean deterministic. Include concrete code examples showing API calls in Python. Cross-reference docs/ai-native-solution-patterns.md as the next document to read after this one.
PROMPT

# ---------------------------------------------------------------------------
# 2. PROMPT ENGINEERING THAT WORKS
# ---------------------------------------------------------------------------
log 2 "Prompt Engineering That Works"
run_deep_dive 2 <<'PROMPT'
Prompt engineering for production systems, not parlor tricks. Focus on the techniques that actually matter in production: how to write system prompts that constrain behavior reliably, when and how to use few-shot examples -- and when they waste tokens --, chain-of-thought prompting and when it helps vs when it hurts -- it can decrease accuracy on simple tasks --, role prompting and its real effect on output quality, output format instructions -- XML tags, JSON schemas, markdown structure -- and why explicit format constraints outperform vague instructions, the difference between instructions and demonstrations, negative prompting -- what NOT to do -- and why it is unreliable, and prompt versioning as a software engineering practice. Provide real before/after prompt examples showing measurable quality improvements. Include the research: OpenAI's finding that chain-of-thought decreased accuracy on simple classification tasks, Anthropic's guidance on XML tag structuring. Address the failure mode where teams endlessly tweak prompts instead of escalating to a different pattern. This is the first practical skill for the audience -- assume they have read the LLM fundamentals doc and can make API calls but have never written a production prompt. Cross-reference docs/ai-native-solution-patterns.md for when to escalate beyond prompt engineering.
PROMPT

# ---------------------------------------------------------------------------
# 3. CONTEXT ENGINEERING
# ---------------------------------------------------------------------------
log 3 "Context Engineering"
run_deep_dive 3 <<'PROMPT'
Context engineering as a discipline -- the practice of deciding what goes into the LLM context window and why. This is the skill that separates working systems from broken ones. Cover: the context window as a budget where every token spent on instructions is a token not available for content, how to structure the context -- system prompt, retrieved context, conversation history, user input -- and the priority order when you must truncate, the lost-in-the-middle phenomenon where LLMs attend more to the beginning and end of long contexts and what it means for information placement, context compression techniques including summarization and selective inclusion and structured extraction, how conversation history management works in practice -- sliding window, summary-based, hybrid --, the relationship between context size and output quality where more context is not always better -- cite the OpenAI Icelandic study where RAG degraded fine-tuned performance --, managing context across multi-step pipelines including what to pass between steps and what to discard, and sub-agents as context management tools following Dex Horthy's insight that sub-agents are for controlling context not anthropomorphizing roles. Include concrete examples showing context budgets for different system types. This fills the gap between knowing how to write a prompt and knowing how to architect what surrounds it.
PROMPT

# ---------------------------------------------------------------------------
# 4. STRUCTURED OUTPUT AND OUTPUT PARSING
# ---------------------------------------------------------------------------
log 4 "Structured Output and Output Parsing"
run_deep_dive 4 <<'PROMPT'
Structured output from LLMs -- how to make model output machine-readable and reliable. Cover: why unstructured text output is the root cause of most integration failures, JSON mode and its limitations across providers -- OpenAI structured outputs, Anthropic tool use for structured output, Gemini JSON mode --, function calling as a structured output mechanism -- not just for tools but using tool definitions to force output schemas --, Pydantic models and type-safe extraction in Python, XML-tagged output for cases where JSON is awkward such as nested prose or mixed content, output validation and retry strategies for when the model produces malformed output, schema design for LLM output -- keep schemas simple, avoid deeply nested structures, provide examples in the schema description --, the tradeoff between strict schemas and model flexibility, and how structured output changes across the pattern spectrum from single call to pipeline to agent. Provide real code examples using the OpenAI and Anthropic SDKs. Include failure modes: schemas that are too complex for the model to fill reliably, validation that rejects correct but differently-formatted output, and retry loops that waste tokens. This is a foundational skill that every subsequent pattern depends on.
PROMPT

# ---------------------------------------------------------------------------
# 5. RAG IMPLEMENTATION
# ---------------------------------------------------------------------------
log 5 "RAG: From Concept to Production"
run_deep_dive 5 <<'PROMPT'
RAG -- Retrieval-Augmented Generation -- implementation from concept to production. This is the most common production pattern after single LLM calls and the existing docs reference it constantly without explaining how to build it. Cover: why RAG exists because the model lacks information not capability, the RAG pipeline architecture -- ingest, chunk, embed, store, retrieve, augment, generate --, chunking strategies and why they matter more than people think -- fixed-size, semantic, document-structure-aware, recursive --, embedding models and how to choose them -- OpenAI ada, Cohere embed, open-source alternatives --, vector databases in practice -- Pinecone, Weaviate, Chroma, pgvector and when to use what --, retrieval methods beyond naive similarity search -- hybrid search combining semantic and keyword/BM25, query rewriting, HyDE --, reranking and why it dramatically improves retrieval quality -- cross-encoders, Cohere Rerank, reciprocal rank fusion --, how to evaluate RAG systems where retrieval metrics and generation metrics are separate problems, citation and source attribution for tracing which chunks influenced the output, the production RAG pipeline -- ingestion scheduling, incremental updates, stale data handling, metadata filtering --, and failure modes specific to RAG -- retrieval misses, context poisoning, chunk boundary problems, the contradiction between retrieved passages. Provide concrete code examples for a complete RAG pipeline. Cross-reference docs/ai-native-solution-patterns.md for when RAG is the right pattern vs when it is not.
PROMPT

# ---------------------------------------------------------------------------
# 6. TOOL DESIGN FOR LLM AGENTS
# ---------------------------------------------------------------------------
log 6 "Tool Design for LLM Agents"
run_deep_dive 6 <<'PROMPT'
Tool design for LLM agents -- the skill Anthropic says they spend more time on than the overall prompt. Cover: what tools are in the LLM context as function definitions the model can choose to call, the anatomy of a good tool definition -- name, description, parameters, examples, error handling --, why tool documentation quality determines agent success more than prompt quality, the function calling protocol across providers -- OpenAI function calling, Anthropic tool use, Gemini function declarations --, MCP or Model Context Protocol as the emerging standard for tool integration -- what it is, how it works, when to use it vs raw function calling --, tool design principles -- single responsibility, clear parameter names, predictable return formats, useful error messages --, common tool categories -- search, file operations, API calls, code execution, database queries -- and design patterns for each, the tool selection problem where giving an agent 50 tools causes confusion and the sweet spot is 5-15 focused tools, sandboxing and permission models for tool execution, and how tool design changes across patterns from single call with tools to agent with tools to multi-agent with shared tools. Include concrete tool definitions in both OpenAI and Anthropic formats. Show before/after examples where better tool documentation dramatically improves agent behavior. Cross-reference docs/ai-native-solution-patterns.md for the autonomous agent and orchestrator-workers patterns that depend on good tool design.
PROMPT

# ---------------------------------------------------------------------------
# 7. AI-NATIVE SOLUTION PATTERNS (regenerating with references)
# ---------------------------------------------------------------------------
log 7 "AI-Native Solution Patterns"
run_deep_dive 7 <<'PROMPT'
AI-native solution patterns -- matching problems to architectures and building each one. Most AI projects fail not because the model is wrong but because the architecture is wrong for the problem. Cover the pattern catalog: single LLM call, prompt chain/pipeline, router, parallelization -- sectioning and voting --, orchestrator-workers, evaluator-optimizer, autonomous agent. For each pattern cover: what it is, when to use it, which problem types match, concrete build stages with exit criteria, and a real-world example. Include the complexity escalation ladder -- start with the simplest pattern that could work and escalate only when evaluation data proves the simpler approach is insufficient. Cover the knowledge enhancement track as an orthogonal axis: RAG vs fine-tuning vs prompt engineering vs distillation with decision criteria and concrete data -- cite the OpenAI Icelandic language study BLEU scores. Cover the failure taxonomy: premature agent-ification, RAG as default answer, skipping evaluation, framework lock-in, the production cliff. Include the evaluation flywheel as a cross-cutting concern. The audience is practitioners deciding which pattern to use for their problem. Cross-reference docs/llm-role-separation-executor-evaluator.md for the evaluator-optimizer pattern and docs/quality-gates-in-agentic-systems.md for gates between pipeline steps.
PROMPT

# ---------------------------------------------------------------------------
# 8. EVALUATION-DRIVEN DEVELOPMENT
# ---------------------------------------------------------------------------
log 8 "Evaluation-Driven Development for LLM Systems"
run_deep_dive 8 <<'PROMPT'
Evaluation-driven development for LLM systems -- how to build the measurement infrastructure that every other document in this suite prescribes but none explains how to construct. Cover: why evaluation must come before architecture because you cannot improve what you cannot measure, the eval flywheel -- error analysis, failure classification, eval construction, targeted improvement, validation --, how to build golden datasets -- size targets of 50 hard cases minimum and 500-2000 for production, stratification by difficulty, refresh cadence --, the three types of evaluation -- code-based deterministic checks, embedding-based similarity, LLM-as-judge -- and when to use each, building LLM-as-judge evaluators -- binary PASS/FAIL over numeric scales, classification over Likert, per-dimension isolation as described in docs/llm-role-separation-executor-evaluator.md --, statistical rigor in eval results -- confidence intervals, significance testing, avoiding p-hacking with small eval sets --, evaluation frameworks in practice -- DeepEval, RAGAS, Braintrust, Promptfoo and when to use which --, continuous evaluation in production -- sampling rates, drift detection, alerting thresholds --, the eval-to-business-metric bridge connecting eval scores to user satisfaction and revenue impact and support ticket reduction, and the anti-pattern of vibes-based development where you change prompt and test a few inputs and ship when it looks good. Provide concrete code examples building an eval suite from scratch. This document should make the reader capable of building the evaluation infrastructure that docs/ai-native-solution-patterns.md requires at every build stage.
PROMPT

# ---------------------------------------------------------------------------
# 9. LLM ROLE SEPARATION (regenerating with references)
# ---------------------------------------------------------------------------
log 9 "LLM Role Separation: Executor vs Evaluator"
run_deep_dive 9 <<'PROMPT'
LLM role separation -- practical methods for isolating executors from evaluators so they cannot influence each other. Cover: the core problem where shared cognition corrupts judgment -- self-preference bias of 10-25%, position bias swinging win-rates up to 80 percentage points, verbosity bias. The failure taxonomy: context leakage, self-preference bias through shared weights, scoring scale collapse, position/verbosity bias, metric proxy collapse. The separation spectrum with 7 levels from no separation through hybrid deterministic+LLM cascade, with code examples at each level. Implementation patterns across real frameworks: per-agent model assignment in AutoGen and CrewAI, context manager model switching in DSPy, pluggable judge models in DeepEval and RAGAS and Braintrust, the dual LLM privileged/quarantined architecture for security, per-dimension isolated judges following Anthropic's guidance, and evaluation cascades for cost optimization. Include the key finding that switching from 1-10 numeric scoring to discrete classification raised accuracy from 95% to 98%. Include the Hugging Face result that a 1-4 rubric scale raised Pearson correlation with humans from 0.567 to 0.843. Cross-reference docs/quality-gates-in-agentic-systems.md for why self-evaluation fails at the cognitive level and docs/self-improving-systems.md for why evaluator independence matters for sustained improvement.
PROMPT

# ---------------------------------------------------------------------------
# 10. QUALITY GATES IN AGENTIC SYSTEMS (regenerating with references)
# ---------------------------------------------------------------------------
log 10 "Quality Gates in Agentic Systems"
run_deep_dive 10 <<'PROMPT'
Quality gates in agentic systems -- why they fail and how to make them reliable. The fundamental problem: every quality gate in an LLM-driven system faces the structural contradiction that the entity being constrained is the same entity interpreting and enforcing the constraint. This is a governance problem not a software engineering problem. Cover the failure taxonomy: rationalization where the model argues itself past constraints, context dilution where gates lose priority as the context window fills, sycophancy from RLHF training biasing toward user-pleasing responses, conflation where the model merges generation and verification into one step, semantic drift where instructions mutate through re-interpretation, and hallucinated compliance where the model claims to have verified without actually checking. Cover the gate reliability spectrum from Level 0 -- prompt-level suggestions at ~50% reliability -- through Level 5 -- external system enforcement at ~99%+. Cover the design principles: pit of success, evidence over claims, adversarial independence, defense in depth, minimizing interpretive surface, making bypass harder than compliance. Grade real quality gate implementations. Cross-reference docs/llm-role-separation-executor-evaluator.md for the evaluator isolation methods.
PROMPT

# ---------------------------------------------------------------------------
# 11. SECURITY AND SAFETY
# ---------------------------------------------------------------------------
log 11 "Security and Safety in LLM Applications"
run_deep_dive 11 <<'PROMPT'
Security and safety in LLM applications -- the threat model and practical defenses for production systems. Cover: the LLM threat landscape where prompt injection is not the only threat but it is the most common, direct prompt injection where a user crafts input to override system instructions with concrete attack examples, indirect prompt injection where malicious content in retrieved documents or tool outputs poisons the model's behavior, jailbreaking vs prompt injection as different problems with different defenses, the defense hierarchy from weakest to strongest -- instruction-based defenses, input sanitization, output filtering, structural separation as described in docs/llm-role-separation-executor-evaluator.md for the dual LLM architecture, sandboxed execution, human approval gates --, PII handling -- detection, redaction before API calls, provider data retention policies, zero-retention contracts --, content filtering and moderation -- pre-call input screening, post-call output screening, the moderation API pattern --, guardrail design -- input validators, output validators, action validators and why guardrails must be external to the LLM not prompt-based as described in docs/quality-gates-in-agentic-systems.md --, the six security patterns from IBM/ETH Zurich research -- Action-Selector, Plan-Then-Execute, LLM Map-Reduce, Dual LLM, Code-Then-Execute, Context-Minimization --, supply chain risks -- model poisoning, dependency attacks on LLM frameworks --, and security testing -- red teaming, adversarial input generation, automated vulnerability scanning. Include concrete defensive code examples. Assume the reader builds systems that handle real user data.
PROMPT

# ---------------------------------------------------------------------------
# 12. MEMORY AND STATE MANAGEMENT
# ---------------------------------------------------------------------------
log 12 "Memory and State Management in Agentic Systems"
run_deep_dive 12 <<'PROMPT'
Memory and state management in agentic systems -- how agents remember, learn, and maintain coherence across interactions. Cover: why memory matters because without it every interaction starts from zero and agents cannot learn from experience, the memory taxonomy where working memory equals the current context window and short-term memory equals conversation history and long-term memory equals persistent storage across sessions, conversation memory strategies -- full history, sliding window, summary-based compression, hybrid approaches -- with concrete code and tradeoff analysis, long-term memory architectures -- vector stores for semantic retrieval, knowledge graphs for structured relationships, key-value stores for exact recall --, the memory-context bridge for selecting what from long-term memory enters the current context window which is where memory meets context engineering, state management in multi-step pipelines -- what to carry forward, what to discard, checkpoint strategies --, progress files and session recovery for long-running agents following Anthropic's harness patterns, memory in multi-agent systems -- shared memory vs private memory and the coordination problem --, experience replay for storing successful trajectories as future few-shot examples following the Voyager skill library pattern from docs/self-improving-systems.md, and practical memory implementations using real tools -- vector databases, Redis, SQLite, file-based approaches. Include concrete code showing a complete memory system for a conversational agent. Address the failure modes: context window overflow from unbounded history, stale memories causing incorrect behavior, and memory retrieval that returns irrelevant context.
PROMPT

# ---------------------------------------------------------------------------
# 13. COST ENGINEERING
# ---------------------------------------------------------------------------
log 13 "Cost Engineering for LLM Systems"
run_deep_dive 13 <<'PROMPT'
Cost engineering for LLM systems -- how to make AI-native solutions economically viable in production. Cover: the cost model where input tokens and output tokens are priced differently and output tokens cost 3-5x more than input tokens across providers, how to estimate cost per request for different patterns -- single call vs pipeline vs agent where agents can be 10-100x more expensive than single calls --, token counting in practice -- tiktoken for OpenAI, Anthropic's token counting, why you need to count before sending --, caching strategies -- exact-match response caching, semantic caching with embedding similarity, Anthropic's prompt caching for repeated prefixes, cache hit rates and break-even analysis --, model routing for cost optimization where you route easy tasks to cheap models and hard tasks to expensive models using the router pattern from docs/ai-native-solution-patterns.md as a cost tool, batch APIs and when they make sense with 50% cost reduction for non-latency-sensitive workloads, cost controls and guardrails -- per-request limits, per-session limits, daily budget caps, alerting thresholds --, the runaway agent problem where one infinite loop can turn hundreds into thousands of dollars overnight with concrete examples, cost monitoring dashboards -- what to track: cost per request, cost per successful outcome, cost per user, cost trend over time --, provider comparison on cost -- OpenAI vs Anthropic vs Google vs open-source on common workloads --, and the build-vs-buy calculation for self-hosted models and when running your own model becomes cheaper than API calls. Include concrete cost calculations for real system archetypes. This should make the reader capable of budgeting and operating an LLM system without surprise bills.
PROMPT

# ---------------------------------------------------------------------------
# 14. OBSERVABILITY AND MONITORING
# ---------------------------------------------------------------------------
log 14 "Observability and Monitoring for LLM Systems"
run_deep_dive 14 <<'PROMPT'
Observability and monitoring for LLM systems -- how to see what is happening inside non-deterministic systems that cannot be debugged with traditional logging. Cover: why LLM observability is different from traditional application monitoring where non-deterministic outputs mean you cannot assert on exact responses and quality is statistical not binary, what to log for every LLM call -- input messages, output, model, temperature, token counts, latency, cost, trace ID --, tracing multi-step pipelines and agents -- parent-child span relationships, how to trace a user request through router to worker to evaluator --, the observability stack for LLM systems -- Langfuse, Helicone, Braintrust, Arize Phoenix, OpenTelemetry with LLM extensions and when to use which --, quality monitoring in production -- sampling strategies: 100% automatic checks, 10-20% LLM-as-judge, 5-10% human review --, drift detection for detecting when model quality degrades over time from provider model updates or changing input distributions or concept drift, alerting that works -- what thresholds to set, how to avoid alert fatigue, the difference between latency alerts and quality alerts --, debugging non-deterministic failures -- reproduction strategies, seed values, temperature=0 for debugging, trace replay --, dashboards that matter -- cost per day, quality score trend, latency p50/p95/p99, error rate by error type, model usage breakdown --, and the feedback loop from monitoring to improvement where production failures feed back into golden datasets and anomaly investigation workflows. Include concrete examples setting up observability for a multi-step pipeline. Cross-reference docs/llm-role-separation-executor-evaluator.md for how evaluation cascades feed into monitoring.
PROMPT

# ---------------------------------------------------------------------------
# 15. HUMAN-IN-THE-LOOP PATTERNS
# ---------------------------------------------------------------------------
log 15 "Human-in-the-Loop Patterns"
run_deep_dive 15 <<'PROMPT'
Human-in-the-loop patterns for AI-native systems -- how to design the boundary between human judgment and machine autonomy. Cover: why full autonomy is almost never the right starting point following the progressive autonomy principle from Anthropic where you start with human approval on all actions and reduce oversight as the system proves itself, the approval workflow architecture -- how to pause an agent, present a decision to a human, resume with the decision with concrete implementation patterns --, the four levels of human involvement -- human-does-it with AI assist, human-approves before AI acts, human-reviews after AI acts, AI-acts-autonomously with human audit --, how to design escalation triggers -- cost thresholds, confidence scores, action categories, anomaly detection and which decisions warrant human review and which do not --, the UX of human-in-the-loop where approval fatigue is real and if you require approval for every action you destroy the value of automation creating the stutter-step agent anti-pattern, handoff protocols between AI and human -- what context to pass, how to summarize the AI's work so far, how to resume after human intervention --, progressive autonomy implementation -- how to measure trust, how to expand the autonomy boundary, rollback when trust is violated --, human-in-the-loop for evaluation -- human labels feeding into eval pipelines, calibration workflows, disagreement resolution --, and the organizational dimension -- who approves what, role-based access control for agent actions, audit trails for compliance. Include concrete implementation patterns. Cross-reference docs/quality-gates-in-agentic-systems.md for the reliability spectrum and docs/ai-native-solution-patterns.md for the agent build stages that require human oversight.
PROMPT

# ---------------------------------------------------------------------------
# 16. MULTI-AGENT COORDINATION
# ---------------------------------------------------------------------------
log 16 "Multi-Agent Coordination"
run_deep_dive 16 <<'PROMPT'
Multi-agent coordination -- the most complex pattern, covered last because you should exhaust every simpler option first. Cover: when multi-agent is genuinely warranted vs when it is over-engineering where docs/ai-native-solution-patterns.md identifies this as less than 0.1% of use cases and explain what makes those cases special, the coordination problem -- how do agents share information, avoid duplicate work, resolve conflicts, and converge to a result --, communication patterns -- shared message bus, direct messaging, hierarchical reporting, blackboard architecture with tradeoffs of each --, orchestration models -- centralized supervisor, decentralized peer-to-peer, hierarchical with sub-orchestrators --, shared state management -- shared memory, event sourcing, conflict resolution when two agents modify the same state --, the MapReduce multi-agent pattern from Anthropic where you split work across independent agents and aggregate results deterministically, agent handoff protocols -- how to transfer a task from one agent to another with sufficient context using the sub-agent-as-tool pattern --, cost and latency reality where multi-agent systems cost 5-10x single agents with concrete numbers from production deployments, failure modes specific to multi-agent -- infinite delegation loops, context contamination between agents, coordination overhead exceeding the value of specialization, cascading failures when one agent breaks --, framework comparison for multi-agent -- AutoGen, CrewAI, LangGraph, custom orchestration and when each makes sense --, and the testing problem -- how to test agent interactions, simulation environments, conversation replay. Include concrete architecture examples for the 2-3 use cases where multi-agent genuinely outperforms alternatives. Cross-reference docs/llm-role-separation-executor-evaluator.md for the per-agent model assignment patterns and docs/self-improving-systems.md for multi-agent self-improvement loops.
PROMPT

# ---------------------------------------------------------------------------
# 17. SELF-IMPROVING SYSTEMS (regenerating with references)
# ---------------------------------------------------------------------------
log 17 "Self-Improving Systems"
run_deep_dive 17 <<'PROMPT'
Self-improving systems -- why most loops plateau and what actually drives sustained gain. The core tension: every self-improving system is a bet that the system can evaluate its own outputs well enough to create a training signal that drives real improvement. Cover the failure taxonomy: the hallucination barrier where same-model generation and evaluation have correlated noise, Goodhart drift where the optimized metric decouples from the actual goal, compounding regression in unmeasured dimensions, distribution narrowing where capability space shrinks, local optima trapping from greedy hill-climbing, and verification cost explosion from diminishing returns. Cover the self-improvement spectrum from Level 0 static pipeline through Level 5 recursive self-modification, with code examples at each level including Self-Refine, STaR, Voyager skill libraries, and SICA. Use Karpathy's autoresearch as the primary case study -- its three-file architecture where prepare.py is immutable and train.py is editable, the hill-climbing loop, the 5-minute fixed compute budget, and results from 700 experiments reducing val_bpb from 0.9979 to 0.9697. Also cover AlphaEvolve's evolutionary approach recovering 0.7% of Google's worldwide compute. Cover the GVU framework and variance inequality from the ICLR 2026 workshop. Cover the 6 principles: separate evaluator from generator, fix compute budget, hill-climbing with escape hatches, measure more than you optimize, persist at the right layer, bound the modification surface. Cross-reference docs/llm-role-separation-executor-evaluator.md for evaluator separation methods.
PROMPT

# ---------------------------------------------------------------------------
# GENERATE READING GUIDE (index.md)
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Generating reading guide: $DOCS_DIR/index.md"
echo "============================================================"
echo ""

cat > "$DOCS_DIR/index.md" << 'INDEX'
# Agentic Engineering: A Practitioner's Guide

From "what is a token" to production multi-agent systems -- 17 deep-dives that build on each other in sequence.

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

---

## Tier 3: Quality and Safety

*How to make systems reliable, secure, and trustworthy in production.*

Read this tier when you have a working system and need to harden it for real users. These documents address the problems that surface when your system handles untrusted input, makes consequential decisions, or runs at scale.

### 9. [LLM Role Separation: Executor vs Evaluator](llm-role-separation-executor-evaluator.md)

**You need this if:** Your system uses the same LLM to both produce and judge its output, or you are building evaluation into your pipeline.

Why shared cognition corrupts judgment. 7 levels of isolation from same-call to hybrid cascade. Implementation patterns across frameworks (AutoGen, CrewAI, DSPy, DeepEval, RAGAS). The evaluation cascade for production cost optimization. Per-dimension isolated judges.

**After reading:** You can architect evaluation so that the judge is genuinely independent of the executor.

### 10. [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md)

**You need this if:** Your agents skip steps, rationalize bad output, or fail quality checks that look correct on paper.

Why self-enforcement fails when the LLM is both worker and inspector. 6 failure modes of quality gates. The gate reliability spectrum (Levels 0-5). Design principles for gates that actually hold. Evidence over claims. Structural enforcement over prompt-based constraints.

**After reading:** You can design quality gates that the LLM cannot rationalize around.

### 11. [Security and Safety in LLM Applications](security-and-safety.md)

**You need this if:** Your system handles user input, processes external data, or makes decisions that affect real people.

The LLM threat model. Direct and indirect prompt injection. The defense hierarchy. PII handling. Content filtering. Guardrail design. The six security patterns (IBM/ETH Zurich). Supply chain risks. Red teaming and security testing.

**After reading:** You understand the threats to your LLM system and can implement layered defenses.

---

## Tier 4: Production Operations

*The infrastructure that keeps systems running, affordable, and improving over time.*

Read this tier when you are moving from prototype to production, or when your production system has operational problems (cost overruns, silent quality degradation, context overflow, user trust issues).

### 12. [Memory and State Management](memory-and-state-management.md)

**You need this if:** Your agents forget context between turns, your long-running agents degrade as conversations grow, or you need persistence across sessions.

The memory taxonomy (working, short-term, long-term). Conversation memory strategies. Long-term memory architectures. The memory-context bridge. Checkpointing for long-running agents. Experience replay. Practical implementations with real tools.

**After reading:** You can build memory systems that give agents coherent, persistent state.

### 13. [Cost Engineering for LLM Systems](cost-engineering.md)

**You need this if:** Your LLM costs are unpredictable, growing, or preventing you from scaling.

The token cost model. Cost estimation per pattern. Caching strategies (exact, semantic, prompt caching). Model routing for cost. Batch APIs. Cost controls and guardrails. The runaway agent problem. Build-vs-buy for self-hosted models.

**After reading:** You can budget, monitor, and optimize the cost of your LLM system.

### 14. [Observability and Monitoring](observability-and-monitoring.md)

**You need this if:** You cannot explain why your LLM system produced a specific output, or you discover quality problems only when users complain.

Why LLM observability differs from traditional monitoring. What to log. Multi-step tracing. The observability stack (Langfuse, Helicone, Braintrust). Quality monitoring and drift detection. Debugging non-deterministic failures. Dashboards that matter.

**After reading:** You can see inside your LLM system and detect problems before users do.

### 15. [Human-in-the-Loop Patterns](human-in-the-loop-patterns.md)

**You need this if:** You need to decide how much autonomy to give your AI system, or you need human oversight without destroying the value of automation.

The four levels of human involvement. Approval workflow architecture. Escalation trigger design. The approval fatigue anti-pattern. Handoff protocols. Progressive autonomy. Audit trails for compliance.

**After reading:** You can design the boundary between human judgment and machine autonomy.

---

## Tier 5: Advanced Architecture

*Patterns for systems that coordinate multiple agents or improve themselves over time. Read these last -- most production systems never need them.*

### 16. [Multi-Agent Coordination](multi-agent-coordination.md)

**You need this if:** You have proven that a single agent cannot handle your task, and simpler patterns (router, orchestrator-workers) are insufficient.

When multi-agent is warranted (less than 0.1% of use cases). Communication patterns. Orchestration models. Shared state management. The MapReduce pattern. Agent handoff protocols. Cost reality (5-10x single agents). Multi-agent failure modes. Framework comparison.

**After reading:** You can design multi-agent systems for the rare cases that genuinely need them, and you know when to avoid them.

### 17. [Self-Improving Systems](self-improving-systems.md)

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
| Measure if my system works | [8. Evaluation](evaluation-driven-development.md) | [9. Role Separation](llm-role-separation-executor-evaluator.md) |
| Prevent prompt injection | [11. Security](security-and-safety.md) | [10. Quality Gates](quality-gates-in-agentic-systems.md) |
| Control costs | [13. Cost Engineering](cost-engineering.md) | [7. Solution Patterns](ai-native-solution-patterns.md) |
| Debug production issues | [14. Observability](observability-and-monitoring.md) | [8. Evaluation](evaluation-driven-development.md) |
| Add human oversight | [15. Human-in-the-Loop](human-in-the-loop-patterns.md) | [10. Quality Gates](quality-gates-in-agentic-systems.md) |
| Coordinate multiple agents | [16. Multi-Agent](multi-agent-coordination.md) | [12. Memory](memory-and-state-management.md) |
| Build self-improving loops | [17. Self-Improving](self-improving-systems.md) | [9. Role Separation](llm-role-separation-executor-evaluator.md) |

---

## About This Suite

Every document follows the same structure: problem diagnosis before solutions, failure taxonomy before recommendations, concrete code before abstract advice. No document assumes you have read any other unless it is listed as a prerequisite.

The documents are opinionated. They reflect the current practitioner consensus (Anthropic, OpenAI, Google, and the broader engineering community) as of March 2026. Where sources disagree, the documents state the disagreement rather than picking a side.

The consistent message across all 17 documents: **start with the simplest approach that could work, measure whether it does, and escalate complexity only when the data demands it.**
INDEX

echo "  Reading guide generated: $DOCS_DIR/index.md"

# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  ALL $TOTAL DEEP-DIVES COMPLETE"
echo "============================================================"
echo ""
echo "Documents generated in: $DOCS_DIR"
echo "Reading guide: $DOCS_DIR/index.md"
echo ""
