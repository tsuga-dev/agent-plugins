---
name: otel-instrumentation
description: "Writes, fixes and audits application OpenTelemetry SDK setup, inferring the runtime, inspecting what is already wired, and gating every code change behind confirmation. Use when adding, fixing, generating or auditing OTel SDK setup in C++, .NET, Go, Java or JVM, Node.js or TypeScript, PHP, Python, Ruby, Rust, or an unknown runtime, and for automatic instrumentation, custom spans, metrics, logs, log correlation, resource attributes, propagation, messaging, local testing, redaction, instrumentation audits or SDK snippets. For Collector YAML and pipelines use otel-collector; to decide which signal to emit in the first place use signal-choice-advisor."
---

# OTel Instrumentation

Use this for application OpenTelemetry SDK work. Runtime docs are authoritative for package names, setup snippets, versions, exporter behavior, and Tsuga-specific configuration. Do not generate SDK setup from memory; if a docs fetch fails, stop and report the setup blocker.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

Search first when language or task is unclear:

```bash
tsuga docs search "OpenTelemetry <language or task>"
```

Infer the runtime from the repository, then fetch its page. The detection cues are the part no command or doc page gives you:

| Language/runtime | Detection cues | Docs path |
|---|---|---|
| C++ | `CMakeLists.txt`, `conanfile.txt`, `vcpkg.json`, `BUILD.bazel`, `*.cc`, `*.cpp`, `*.hpp` | `tsuga docs get data-collection/cpp` |
| .NET / C# / F# | `.csproj`, `.fsproj`, `.sln`, `Program.cs`, `Startup.cs`, `appsettings*.json` | `tsuga docs get data-collection/dotnet` |
| Go | `go.mod`, `go.sum`, `*.go`, `go.opentelemetry.io/otel` imports | `tsuga docs get data-collection/go` |
| Java / Kotlin / Scala | `pom.xml`, `build.gradle`, `build.gradle.kts`, `build.sbt`, `src/main/java`, `src/main/kotlin`, `-javaagent` in start scripts | `tsuga docs get data-collection/java` |
| Node.js / TypeScript | `package.json`, `tsconfig.json`, `@opentelemetry/*` dependencies, `--require`/`--import` in `NODE_OPTIONS` or start scripts | `tsuga docs get data-collection/nodejs` |
| PHP | `composer.json`, `public/index.php`, `artisan`, `bin/console`, `php-fpm` config | `tsuga docs get data-collection/php` |
| Python | `pyproject.toml`, `requirements.txt`, `setup.py`, `opentelemetry-instrument` in entrypoints, `wsgi.py`/`asgi.py` | `tsuga docs get data-collection/python` |
| Ruby | `Gemfile`, `config.ru`, `config/application.rb`, `config/initializers/`, `sidekiq.yml` | `tsuga docs get data-collection/ruby` |
| Rust | `Cargo.toml`, `src/main.rs`, `src/lib.rs`, `tracing`/`tokio`/`opentelemetry` dependencies | `tsuga docs get data-collection/rust` |

Each language page carries install, bootstrap, environment variables, traces, metrics, and logs for that runtime. The per-runtime traps — initialization order, shutdown and flush paths, provider lifetime, agent-versus-SDK conflicts, context across async and worker boundaries — are listed per language under `Check high-risk language paths` in `tsuga docs get data-collection/guides/how-to-audit-opentelemetry-instrumentation`. Read that section and the language page before writing code, rather than recalled SDK rules.

Fetch shared docs as needed:

| Need | Docs path |
|---|---|
| OTLP endpoint, header, and signal paths | `tsuga docs get data-collection/forward-to-tsuga/configure-otlp-export` |
| Resource attributes | `tsuga docs get data-collection/guides/how-to-add-resource-attributes` |
| Where each OTel field lands in Tsuga | `tsuga docs get data-collection/guides/default-mapping-for-opentelemetry-formats` |
| Signal choice | `tsuga docs get data-collection/guides/how-to-choose-a-telemetry-signal` |
| Log-trace correlation | `tsuga docs get data-collection/guides/how-to-correlate-logs-and-traces` |
| Trace context propagation | `tsuga docs get data-collection/guides/how-to-propagate-trace-context` |
| Messaging propagation | `tsuga docs get data-collection/guides/how-to-send-traces-through-messaging` |
| Span kind | `tsuga docs get data-collection/guides/how-to-choose-a-span-kind` |
| Instrumentation audit | `tsuga docs get data-collection/guides/how-to-audit-opentelemetry-instrumentation` |
| Local testing before deploy | `tsuga docs get data-collection/guides/test-telemetry-locally` |
| Collector-side redaction and transforms | `tsuga docs get data-collection/guides/how-to-transform-and-redact-telemetry` |
| Missing telemetry | `tsuga docs get data-collection/guides/how-to-troubleshoot-missing-telemetry` |
| Validate arrival in Tsuga | `tsuga docs get data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga` |

## Signal Scope

State the scope explicitly before proposing changes, for example `Signal scope: traces yes, logs yes, metrics no`.

A broad request (`add OTel`, `instrument this service`, `set up observability`) means all three signals. `how-to-correlate-logs-and-traces` above splits OTLP log export, which carries `trace_id` and `span_id` on the records, from the stdout-and-file path, where the collector promotes them. Scope accordingly: a request for trace IDs in logs is usually only the second path. Both can be active at once and double-export the same record.

## Preflight

1. Infer the runtime from manifests, imports, entrypoints, and deployment files.
2. Read the existing setup before proposing code: providers, exporters, instrumentors, propagators, logger bridges, shutdown hooks, `OTEL_*` config, `-javaagent`, `opentelemetry-instrument`.
3. Mark each in-scope signal `implement from scratch`, `add missing piece`, or `audit only`.
4. Do not duplicate a provider or an instrumentation that is already present.

## Mutation Gate

Before generating setup code, custom span/metric/log-correlation snippets, config snippets, or writing any source file:

1. Show the proposed change and why it is needed.
2. Wait for explicit user confirmation (`yes`, `no`, or selected changes).
3. Apply only after confirmation.

Generated code reads endpoints, service name, resource attributes, and keys from environment variables. Never hardcode an ingestion key, operation key, account ID, token, or endpoint URL.

## Source Reading Safety

- Never read `.env`, `*.secret`, `*credentials*`, or `*token*`; if encountered, flag and stop.
- Never reproduce a key, token, account ID, or endpoint URL found in source.
- Label every finding `source: code analysis` or `source: tsuga CLI`.

## Verification

Code that compiles is not telemetry that arrived. Do not state that a signal reaches Tsuga without a command and a returned value. One arrival check per in-scope signal, with the window bounded explicitly rather than left to the CLI default:

```bash
tsuga logs search   --query "context.service.name:<service>" --from <deploy-time> --to now --max-results 10
tsuga traces search --query "context.service.name:<service>" --from <deploy-time> --to now --max-results 10
tsuga aggregation scalar -d '{"dataSource":"metrics","timeRange":{"from":<deploy-time-unix-seconds>,"to":<now-unix-seconds>},"queries":[{"aggregate":{"type":"count","field":"<metric.name>"},"filter":"*"}]}'
```

Metrics need at least one full export interval inside the window before absence means anything. `tsuga metrics list` and `tsuga metrics get` read a name catalog, not the window, so the count is the only arrival evidence (`tsuga docs get explore/guides/how-to-troubleshoot-an-empty-query-result`). An empty result proves nothing about the cause: hand off to `tsuga-debug-telemetry-ingestion`, which owns classification and the debugging path. For the indexing delay, the name catalog, the UI walkthrough and the per-signal correlation checks, use `tsuga docs get data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga`.

## Output Template

```markdown
## Summary
## Signal Scope
## Evidence Used
## Preflight
## Proposed Change
## Verification
## Limitations
```

## Related Skills / Next Steps

- `signal-choice-advisor` - metric vs span vs log decisions, semantic convention naming, and cardinality.
- `otel-collector` - Collector YAML, processors, OTTL, routing, filtering, and redaction.
- `tsuga-debug-telemetry-ingestion` - diagnose missing, sparse, or uncorrelated telemetry after setup.

## Limitations

- Runtime docs are authoritative for setup code, package versions, and exporter behavior.
- This skill keeps only cross-language workflow, runtime detection, and the evidence discipline, not SDK reference material.
