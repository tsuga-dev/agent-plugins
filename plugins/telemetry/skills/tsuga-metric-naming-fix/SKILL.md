---
name: tsuga-metric-naming-fix
description: "Use when metric names violate OTel naming conventions (dot notation, no units/service/env in name) or need to be renamed."
---

# Metric Naming Fix

## Trigger

"Fix my metric names", "Rename metrics to OTel conventions", "Apply the naming fixes from the audit", "Fix the underscores in my metric names", "Rename metrics to use dot notation", "Our metrics don't follow OTel naming — fix them"

## Required Inputs

- **Service name or metric name filter** (required — ask if missing)
- **Source code path** (required — ask if missing; renames are code changes and cannot be applied without it)

## Workflow

1. `tsuga metrics list` — enumerate metrics for the service; identify naming violations using OTel naming rules:

   OTel naming rules:
   - Dot notation, not underscores: `http.server.request.duration` not `http_server_request_duration`
   - No service name in metric name: service identity belongs in `service.name` resource attribute
   - No environment or version in metric name: `prod_`, `v2_` prefixes are violations
   - No units in metric name: use `unit` metadata field instead of `_ms`, `_bytes` suffixes
   - Verb-object pattern: `http.server.request.duration` not just `duration`
   - Use OTel semantic conventions before custom names

   Violation checklist:
   - Underscores instead of dot notation
   - Service name encoded as metric name prefix
   - Environment or version prefix (`prod_`, `staging_`, `v2_`)
   - Unit suffix in metric name (`_ms`, `_bytes`, `_count`)

2. Read source code at the provided path — find metric creation call sites by searching for each violating metric name. For each: note the file path, line number, and current name.
   - Skip any metric where aggregation data is absent in Tsuga (may already be unused) — flag as "no data, skipping" and do not include in rename proposals.

3. For each proposed rename: check downstream impact before presenting to the user:
   - `tsuga monitors list` — any monitor whose filter references the old metric name?
   - `tsuga dashboards list` — any dashboard using the old metric name?
   - Collect all impacted assets; they must be updated manually after the code rename (the CLI cannot rename dashboard or monitor references).

4. Build the rename table: old name → new name following OTel naming rules, with the rule violated for each.

5. **Mutation gate.** Present the rename table and wait for explicit confirmation before making any changes:

   ```
   ## Proposed Metric Renames
   | Current Name | Proposed Name | Rule Violated | Files Affected |
   |---|---|---|---|
   | <old> | <new> | <rule> | <path:line> |
   ```

   ### Confirm Before Applying

   Before applying any code change (new file, edit, rename, dependency change):

   1. Show the proposed change (diff, code block, or table) with a brief explanation of WHY
   2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
   3. Apply only after confirmation

   After deploy, recommend running `tsuga-smoke-test` to verify — do not block on it or treat it as a required step.

   Proceed with these renames? (yes / no / select specific ones)

   Do not apply any changes until the user responds with an explicit "yes" or selection.

6. On "yes" (or selection): apply renames using the Edit tool at each cited file + line.

7. Remind the user to update any monitors and dashboards that referenced the old names.

## Evidence Requirements

- Each proposed rename cites: current name, rule violated (OTel naming rules: dot notation, no service/env/unit in name), file path + line number, corrected name
- Downstream impact cites: asset name, asset type (monitor / dashboard), old name as referenced
- "No aggregation data" skip = zero results from `tsuga metrics get <name>` or no time-series data — flag explicitly

## Output Template (post-confirmation)

```
## Metric Renames Applied

| Old Name | New Name | File | Line |
|---|---|---|---|
| <old> | <new> | <path> | <N> |

## Skipped (no aggregation data — may be unused)
- <metric.name>

## Downstream Assets Requiring Manual Update
| Asset | Type | Old Name Referenced |
|---|---|---|
| <name> | monitor / dashboard | <old.metric.name> |

No downstream assets found. / <N> assets require manual update — see list above.

## Verification
Run `tsuga metrics list` in ~60s to confirm new names appear.
Run `tsuga-smoke-test` for <service> to confirm signal continuity after redeployment.

## Limitations
- Renames applied to source files at cited paths only; other metric definitions may exist elsewhere
- Dashboard and monitor references must be updated manually — the CLI cannot apply these changes
- Old metric name will continue to appear in Tsuga until the service redeploys with the renamed metric
- Rename proposals follow OTel naming rules; always verify the proposed name against your domain conventions before confirming
```

## Related Skills / Next Steps
- `tsuga-audit-metrics` — full audit before deciding what to rename
- `tsuga-smoke-test` — verify metrics after renaming and redeployment
- `otel-instrumentation` — cross-signal audit including metric naming (routes to per-lang `references/audit-checklist.md`)

## Safety Rules

- **Never apply renames without explicit user confirmation** — show proposed changes and wait for confirmation before applying; the user must respond with "yes" or a specific selection
- Never rename a metric that has no aggregation data in Tsuga — flag it as possibly unused and skip
- Downstream impact check (monitors, dashboards) is required before presenting the confirmation prompt
- After applying: recommend `tsuga-smoke-test` to verify signal continuity after redeployment — do not block on it
- Never read `.env`, `*.secret`, `*credentials*`, or `*token*` files — flag and stop if encountered
- Never reproduce raw attribute values from CLI output — inspect names and types only
- If source code path is not provided: do not propose renames — inform the user that a code path is required and stop

**Instrumentation Quality Rules (A1–A5):**

A1: Code reading is allowed and expected — reading source files is how you gather evidence.
A2: Label all findings with their evidence source: "source: tsuga CLI" or "source: code analysis".
A3: Refactor proposals require explicit user confirmation before writing code.
A4: Validate your understanding of existing instrumentation before concluding anything is missing.
A5: Distinguish advisory findings (suspected issues) from verified findings (confirmed via CLI data).
