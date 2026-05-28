# Deploy & Config Drift Playbook

For "it was fine yesterday" incidents. Most are a change — code, config, secret, flag, IAM policy, quota, or schema.

Concrete commands in `$gh`. This file is reasoning disambiguation only.

## Merged ≠ deployed

A merged PR is a candidate only if a deploy completed after merge and before incident start.

Verify deployment status:
- GitHub Actions: `gh run list -R owner/repo --workflow deploy.yml --conclusion success --created ">=<date>"`.
- ArgoCD / Flux: check sync status and the image tag actually deployed.
- Vercel / similar: check production deployment URL + commit SHA.
- Manual deploys: ask. Don't assume.

## Config vs code

- Config change (env, ConfigMap, YAML, flag) → often reversible by redeploying old config. Lower blast radius.
- Code change → revert commit or roll back image.
- Secret rotation → rarely rolled back; usually forward-fix (rotate again, update consumers).

Category: `configuration_error` for first, `code_defect` for second.

## Feature flags

- Check flag flip timestamps in the window, not just deploys. A flip is a production change with no commit.
- "Off in prod" can still be a trigger if the flag gates a safety path.

## IAM and key rotation

- Token rotation → who rotated, what consumers hold the old token, when the overlap window was supposed to expire.
- IAM policy change → what permission was removed, what service needed it, was the change intended.
- Cert rotation → expiry date, consumers validating old fingerprint.

These are almost always `configuration_error` or `infrastructure`, not `code_defect`.

## Schema / upstream API

- New required field from upstream API, removed field, changed enum → `data_quality`, even if the symptom is your 5xx.
- Schema migration with long backfill → expect lock pressure, replica lag, write amplification. Correlate with migration-start timestamp, not PR merge.

## Misleading context

- Release tag ≠ shipped to every environment. Check per-env rollout.
- Green CI ≠ works in prod; only proves build + unit tests.
- Dependabot / vacation-time commits are still real changes — often cause incidents.

## Causal chain skeletons

- Config drift: env var renamed in repo → old env still set in prod → service reads empty → auth header empty → 401.
- Unsafe migration: migration PR merged → deploy runs migration → ALTER TABLE exclusive lock → writes blocked → queue grows → timeouts.
- Silent flag flip: ops flipped flag at 13:50 → new code path loads from S3 → bucket policy denies → fail open with zero rows.
