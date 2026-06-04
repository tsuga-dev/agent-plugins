# Tsuga Investigation Rules

Use these defaults:

1. Start with `tsuga services list|get`.
   Resolve canonical service, env, team, versions, and whether logs/traces exist.

2. Check `tsuga config` (active key, default cluster).
   Override `--from`, `--to`, and `--max-results` explicitly.
   On multi-cluster orgs, `aggregation` bodies need a `"clusterId"` field.

3. Prefer high-signal commands first.
   - `tsuga logs new-error-patterns`
   - `tsuga logs error-pattern-increases`
   - `tsuga logs patterns`
   - `tsuga aggregation scalar|timeseries`

4. Use `aggregation` for claims.
   Counts, rates, latency, queue growth, and comparisons should come from aggregation, not from eyeballing raw search results.

5. Remember the CLI limits.
   - `metrics list|get` are metadata only
   - monitor commands expose definitions, not live firing truth
   - `aggregation` requires epoch seconds
   - `quality-reports` are posture context, not real-time truth

6. Compare a bad window against a control window whenever possible.

7. Stop at subsystem diagnosis if the trigger is still missing.

Read-only commands to prefer:
- `logs search`
- `logs patterns`
- `logs new-error-patterns`
- `logs error-pattern-increases`
- `traces search`
- `metrics list|get`
- `aggregation scalar|timeseries`
- `services list|get`
- `dashboards list|get`
- `monitors list|get`
- `teams list|get`
- `quality-reports list`
- `config`
