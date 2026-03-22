# Agentic Engineering: A Practitioner's Guide

17 deep-dive documents covering everything from "what is a token" to production multi-agent systems. Built for software engineers who need to put AI-native solutions into production.

## Who This Is For

You are an experienced software engineer. You may have used ChatGPT, but you have never built a production system that calls an LLM API. Or maybe you have, but your system is unreliable, expensive, or impossible to debug. Either way, you need practical guidance -- not hype, not theory, not vendor marketing.

Every document in this suite follows the same structure: diagnose the problem before proposing solutions, provide concrete code examples for every claim, and cite verifiable sources so you can confirm nothing is fabricated.

## Start Here

**[Read the full guide](docs/index.md)** -- includes a 5-tier reading path, per-document summaries, and a problem-pattern lookup table.

Or jump directly to what you need:

| I need to... | Start here |
|---|---|
| Understand how LLMs work | [LLM Fundamentals](docs/llm-fundamentals-for-practitioners.md) |
| Write reliable prompts | [Prompt Engineering](docs/prompt-engineering.md) |
| Give my LLM access to my data | [RAG Implementation](docs/rag-from-concept-to-production.md) |
| Build an agent with tools | [Tool Design](docs/tool-design-for-llm-agents.md) |
| Choose the right architecture | [Solution Patterns](docs/ai-native-solution-patterns.md) |
| Measure if my system works | [Evaluation-Driven Development](docs/evaluation-driven-development.md) |
| Prevent prompt injection | [Security and Safety](docs/security-and-safety.md) |
| Control costs | [Cost Engineering](docs/cost-engineering-for-llm-systems.md) |
| Debug production issues | [Observability](docs/observability-and-monitoring.md) |

## What's Inside

**Tier 1 -- Foundations:** LLM fundamentals, prompt engineering, context engineering, structured output

**Tier 2 -- Core Patterns:** RAG, tool design, solution pattern selection, evaluation

**Tier 3 -- Quality and Safety:** Executor/evaluator separation, quality gates, security

**Tier 4 -- Production Operations:** Memory management, cost engineering, observability, human-in-the-loop

**Tier 5 -- Advanced:** Multi-agent coordination, self-improving systems

Each document is 3,000-5,000 words with Mermaid diagrams, comparison tables, working code examples, and a References section with clickable URLs to every source consulted.

## Repository Structure

```
docs/              17 deep-dive documents + index reading guide
.claude/commands/  The /deep-dive skill definition used to generate each document
tools/             Generation script (maintainer use only)
```

## For Maintainers

The documents were generated using [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the `/deep-dive` command. The skill definition is included at `.claude/commands/deep-dive.md` so anyone who clones this repo can use it.

To regenerate the full suite:

```bash
cd tools
chmod +x generate-deep-dives.sh
./generate-deep-dives.sh
```

To regenerate from a specific step (e.g., after a failure at step 5):

```bash
RESUME_FROM=5 ./generate-deep-dives.sh
```

## License

This work is licensed under [CC BY-SA 4.0](LICENSE). You are free to share and adapt this material with attribution.
