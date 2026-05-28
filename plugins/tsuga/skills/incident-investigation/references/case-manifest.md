# Case Manifest Contract

Use this when the user can provide paths and context up front.

Minimal JSON shape:

```json
{
  "incident_ref": "INC-1234",
  "summary": "Short human summary of the incident",
  "time_window": {
    "from": "2026-04-10T09:30:00Z",
    "to": "2026-04-10T11:30:00Z"
  },
  "scope": {
    "services": ["web-backend"],
    "clusters": ["prod-mtc"],
    "customers": [],
    "teams": [],
    "envs": ["prod"]
  },
  "paths": {
    "incident_archive": "/abs/path/to/incident-reports",
    "codebases": [
      "/abs/path/to/repo-one",
      "/abs/path/to/repo-two"
    ]
  },
  "repos": [
    "owner/repo-one",
    "owner/repo-two"
  ],
  "known_hints": [
    "started after deploy",
    "possible key rotation"
  ],
  "constraints": {
    "read_only": true
  }
}
```

Use the manifest when it exists. If it does not, reconstruct the same fields from the prompt and only ask for the missing minimum.
