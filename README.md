# Tsuga toolkit for AI coding agents

Official agent plugin published by [Tsuga](https://tsuga.com), shipped as a single marketplace.

## `tsuga`

Operating Tsuga itself: the `tsuga` CLI driver (TQL, aggregations, deep links), live-platform investigation (service health, errors, latency, monitor coverage), dashboard building, an incident-investigation orchestrator, meta-skills for building knowledge-company / incident-history bundles, and OpenTelemetry instrumentation guidance across nine languages (Python, Go, Node.js, Java, .NET, Ruby, Rust, PHP, C++): SDK setup, traces, metrics, logs, trace-log correlation, Collector configuration, OTTL, semantic conventions, instrumentation-quality audits, and telemetry debugging. Live Tsuga workflows require a Tsuga account.

## Install

The [Tsuga CLI](https://www.npmjs.com/package/@tsuga/cli) adds the marketplace and installs the plugin in one command:

```bash
npm install -g @tsuga/cli

# Claude Code
tsuga install plugin claude-code

# Codex
tsuga install plugin codex
```

For Claude Code, this enables marketplace auto-update so the plugin refreshes on its own (pass `--no-auto-update` to skip).

Or add the marketplace and install the plugins directly:

```bash
# Claude Code
claude plugin marketplace add tsuga-dev/agent-plugins
claude plugin install tsuga@tsuga

# Codex
codex plugin marketplace add tsuga-dev/agent-plugins
codex plugin add tsuga@tsuga
```

### OpenCode

> [!IMPORTANT]
This has only been tested with opencode v1, as v2 is still in beta.

Add the skills URL to your `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "urls": ["https://raw.githubusercontent.com/tsuga-dev/agent-plugins/main/plugins/tsuga/skills/"]
  }
}
```

You can replace `main` with any valid SHA of the repository to pin the skills if you want to opt-out of "auto update".

The trailing slash is required. OpenCode fetches `index.json` from that URL, discovers all skills, and downloads them to `~/.cache/opencode/skills/`.

## Ownership & contributions

Tsuga owns and maintains this plugin — anything generic about operating Tsuga or instrumenting with OpenTelemetry belongs here, and installs with `autoUpdate` receive new versions automatically.

- **Found a gap or an error?** Open an issue. Field-tested corrections (a workflow the skill should cover, a gotcha it gets wrong) are exactly what we want to hear about. Please don't send a pull request against this repository: the skill files here are published from Tsuga's own repository, so a change made here would be overwritten rather than kept.
- **Org-specific conventions** (your naming schemes, internal runbooks, metric families, team structure) don't belong in these skills. Keep them in your own plugin layered on top — skills compose, and yours can reference these by name (e.g. `tsuga-cli`).
