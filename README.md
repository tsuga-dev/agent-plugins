# Tsuga toolkit for AI coding agents

Official agent plugins published by [Tsuga](https://tsuga.com), shipped as a single marketplace.

## `tsuga`

Operating Tsuga itself: the `tsuga` CLI driver (TQL, aggregations, deep links), live-platform investigation (service health, errors, latency, monitor coverage), dashboard building, an incident-investigation orchestrator, and meta-skills for building knowledge-company / incident-history bundles. Requires a live Tsuga account.

## `telemetry`

Adding and auditing OpenTelemetry in a codebase across nine languages (Python, Go, Node.js, Java, .NET, Ruby, Rust, PHP, C++): SDK setup, traces, metrics, logs, trace-log correlation, Collector configuration, OTTL, semantic conventions, plus instrumentation-quality audits, smoke-testing, and telemetry-debugging. The audit/debug/smoke skills need the `tsuga` CLI binary on the machine.

## Install

```bash
# Claude Code
claude plugin marketplace add tsuga-dev/agent-plugins
claude plugin install tsuga@tsuga
claude plugin install telemetry@tsuga

# Codex
codex plugin marketplace add tsuga-dev/agent-plugins
codex plugin add tsuga@tsuga
codex plugin add telemetry@tsuga
```
