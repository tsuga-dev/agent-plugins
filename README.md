# Tsuga toolkit for AI coding agents

Official agent plugin published by [Tsuga](https://tsuga.com), shipped as a single marketplace.

## `tsuga`

Operating Tsuga itself, in six job skills and one CLI skill:

- `tsuga-query-data`: the main index. TQL, aggregation bodies, PromQL, metric and field lookup, deep links, and docs lookup.
- `tsuga-investigate`: incidents and root-cause analysis, service health, errors, latency, single traces, and contrast sets.
- `tsuga-audit`: configuration review. Quality report, monitor and SLO coverage, notification routing, dashboards, metrics, and telemetry quality.
- `tsuga-build-assets`: create, update, and delete dashboards, monitors, SLOs, notification rules, routes, policies, and other assets.
- `tsuga-collect-data`: OpenTelemetry instrumentation across nine languages (Python, Go, Node.js, Java, .NET, Ruby, Rust, PHP, C++), Collector configuration, OTTL, signal choice, and missing-data diagnosis.
- `tsuga-design`: what to measure or configure and how to verify it. Objectives, SLIs, signal choice, team, access and retention strategy.
- `tsuga-cli`: running the CLI itself. Install, auth, configuration, commands and flags, output, exit codes, and which commands need confirmation.

It also ships meta-skills for building and validating knowledge-company and incident-history bundles. Live Tsuga workflows require a Tsuga account.

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
Tested with opencode v1 only. opencode v2 is in beta.

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
