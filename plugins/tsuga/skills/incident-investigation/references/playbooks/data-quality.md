# Data Quality & Upstream Change Playbook

For symptoms about the **shape** or **content** of data: empty output, null surge, schema mismatch, row-count anomaly, decoded-but-wrong values, "the numbers look wrong."

## Empty vs dropped rows

- **Zero rows out** with nonzero input → filter / transform / auth rejecting everything. Upstream fine.
- **Partial rows** with nonzero input → schema/validation path dropping a subset. Find the discriminator (tenant, record type, field value).
- **Zero rows in** → problem is upstream. `dependency_failure` or `data_quality` at source.

## Schema drift

- New required field in upstream payload → consumer deserializer fails → all records drop. `data_quality`.
- Existing field type change (string→int, nullable→non-null) → decode errors, silent misparsing, or cast failures.
- Field renamed → hardest to spot; producer keeps sending, consumer maps old field to default.

Check whether the upstream team shipped in the window before blaming your pipeline.

## Null surge

- Sudden NULL spike on previously non-null column → producer falling back silently, or ETL step losing the field.
- Pair with a trace: find the span populating the field, check for swallowed error tags.

## Row-count anomaly

- 10× spike or drop vs same hour last week → something changed. Verify input count at the same boundary before investigating processing.
- Seasonal effects (weekend, holiday, TZ rollover) explain many "anomalies." Check same hour, same day last week.

## Upstream audit

For pipelines consuming external APIs / feeds:
- S3 audit payloads, vendor audit logs, webhook delivery records are source of truth for what arrived.
- If they show a schema change, root cause is upstream even if the symptom is your error. `data_quality`, causal chain starts at the upstream change.

## Silent-failure patterns

- `try/except` → log warning → return None. Record lost, no error metric rises. Watch output-count drops even when error rates look flat.
- Fallback-to-default deserialization. Data "processed" but with zeros. Watch for anomalous floors in distributions.
- Dead-letter table nobody monitors. Pipeline looks healthy while dropping X% of records.

Recovery from silent failure usually requires backfill, not just a deploy.

## Misleading context

- Flat-zero dashboard is LOUDEST signal, not quietest. Flat-zero is rarely natural traffic.
- Downstream monitor on data absence can mislead. Trace upstream: input → transform → output.
- Recent schema PR in your own repo may look like the cause but be a **response** to an earlier upstream change.

## Causal chain skeletons

- Upstream schema change: vendor adds new required enum → deserializer throws on unknown → handler returns None → zero rows written → downstream aggregate empty.
- Silent default: deserializer falls back to `0.0` on parse error → metrics "flat at zero" → no error count rise → dashboards quiet but wrong.
- TZ boundary: producer rolled into new day 8h before consumer expected → hourly partition empty → alert on absent data.
