# Tsuga toolkit for AI coding agents

Official agent plugins published by [Tsuga](https://tsuga.com), shipped as a single marketplace.

## `tsuga`

Operating Tsuga itself: the `tsuga` CLI driver (TQL, aggregations, deep links), live-platform investigation (service health, errors, latency, monitor coverage), dashboard building, an incident-investigation orchestrator, and meta-skills for building knowledge-company / incident-history bundles. Requires a live Tsuga account.

## `telemetry`

Adding and auditing OpenTelemetry in a codebase across nine languages (Python, Go, Node.js, Java, .NET, Ruby, Rust, PHP, C++): SDK setup, traces, metrics, logs, trace-log correlation, Collector configuration, OTTL, semantic conventions, plus instrumentation-quality audits, smoke-testing, and telemetry-debugging. The audit/debug/smoke skills need the `tsuga` CLI binary on the machine.

## Install

The [Tsuga CLI](https://www.npmjs.com/package/@tsuga/cli) adds the marketplace and installs the plugin in one command:

```bash
npm install -g @tsuga/cli

# Claude Code
tsuga install plugin claude-code --include-telemetry

# Codex
tsuga install plugin codex --include-telemetry
```

`--include-telemetry` also installs the `telemetry` plugin; drop it to install only `tsuga`. For Claude Code, this enables marketplace auto-update so the plugins refresh on their own (pass `--no-auto-update` to skip).

Or add the marketplace and install the plugins directly:

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

## Ownership & contributions

Tsuga owns and maintains these plugins — anything generic about operating Tsuga or instrumenting with OpenTelemetry belongs here, and installs with `autoUpdate` receive new versions automatically.

- **Found a gap or an error?** Open an issue or PR. Field-tested corrections (a workflow the skill should cover, a gotcha it gets wrong) are exactly what we want flowing back upstream.
- **Org-specific conventions** (your naming schemes, internal runbooks, metric families, team structure) don't belong in these skills. Keep them in your own plugin layered on top — skills compose, and yours can reference these by name (e.g. `tsuga-cli`).
