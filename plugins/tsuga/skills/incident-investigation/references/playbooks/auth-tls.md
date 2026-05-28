# Auth, TLS & Credentials Playbook

For 401/403 spikes, token errors, cert warnings, SSO failures, or "it works for some customers."

## Cert expiry

- Hard symptom: TLS handshake failures, "certificate has expired", clients retry with same failure.
- Category: `infrastructure` (cert lifecycle) or `configuration_error` (auto-renewal misconfigured).
- Check cert `NotAfter` directly. In the past → cert is cause. Months away → not cert expiry; move on.
- Partial failures (some clients work) often = chain/intermediate issue, not leaf cert.

## Token / key rotation

- No overlap window → old-token holders all fail at rotation time. `configuration_error`.
- With overlap window → expect slow tail as cached tokens refresh. Dozens per hour = normal; thousands per minute = not.
- Service-account key rotation is the most common cause of "broke at 02:00, nobody deployed."

## IAM policy drift

- Policy change removing a permission → affected service fails on next call. `configuration_error`.
- Look for `AccessDenied` / `Forbidden` / 403 in logs; trace to exact API + role/policy name.
- Cross-account role changes break silently until an assume-role call fails.

## Session / OAuth / SSO

- OIDC provider outage → login + session-refresh failures. `dependency_failure`.
- Clock skew on verifier → JWT `iat` / `exp` fail. `infrastructure`.
- IDP key rollover without verifier picking up new JWKS → signature validation fails. Check verifier JWKS cache TTL.

## "Works for some customers"

- Tenant config: customer may have own OAuth client, webhook secret, or API key that rotated independently.
- Region / edge: CDN or edge rule affecting a subset.
- Feature flag: flipped for one cohort.

Don't conclude "service broken" from a partial failure — find the partition first.

## Misleading context

- A 401 in logs is not proof of an auth fault. Misconfigured client can 401 against a healthy server.
- "TLS error" in an HTTP library can mask DNS or TCP.
- Cert-manager / renewal that "ran successfully" can still have failed to install the renewed cert on the listener. Check the listener, not the renewer.

## Causal chain skeletons

- Cert expiry: auto-renew hook disabled weeks ago → cert expires at NotAfter → handshake fails → all HTTPS clients error → 5xx.
- Token rotation: secret rotated in vault → consumer pods hold old token until restart → requests fail at refresh interval → partial outage following restart schedule.
- IAM drift: policy cleanup merged → role loses `s3:GetObject` on one bucket → first S3 read fails → empty response → downstream data-quality alert.
