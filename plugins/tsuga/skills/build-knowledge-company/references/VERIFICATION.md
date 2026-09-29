<!-- skill-lint: allow-forbidden-examples — the gates name the forbidden patterns they hunt -->

# VERIFICATION — acceptance gates for a generated `knowledge-company`

- [Start with the linter](#start-with-the-linter) — what `lint-all.sh` already covers
- [Gate A — sampled command execution](#gate-a--sampled-command-execution)
- [Gate B — aggregation body sanity](#gate-b--aggregation-body-sanity)
- [Gate C — team cross-link](#gate-c--team-cross-link)
- [Gate D — human eyeball](#gate-d--human-eyeball)
- [When a gate fails](#when-a-gate-fails)

## Start with the linter

`check-skill-health` ships the structural checks. Run both passes over the generated skill:

```bash
LINT=${CLAUDE_PLUGIN_ROOT}/skills/check-skill-health/scripts/lint-all.sh
bash "$LINT"           skills/knowledge-company/
bash "$LINT" --audit-commands skills/knowledge-company/
```

Between them they cover: SKILL.md frontmatter and length; the required top-level
`COMPANY_GENERAL_KNOWLEDGE.md` / `COMPANY_TELEMETRY_KNOWLEDGE.md` and the absence of
`RAW_TELEMETRY_KNOWLEDGE.md`; a `TEAM_KNOWLEDGE.md` in every team dir and a `SERVICE_KNOWLEDGE.md`
in every service dir; the canonical section headings in both; file references from SKILL.md
resolving; and the forbidden-token sweep (tool pseudo-syntax, `rtk` prefix, singular resource
verbs, `tsuga spans search`, `--limit` on a telemetry search). `--audit-commands` adds a read-only audit
of the first `tsuga` command in a random sample of dossiers — it inspects shape, it does not run
anything.

Exit code 0 on both is the bar. WARNs are informational; read them and decide.

The four gates below are what the linter cannot reach. Run them by hand.

## Gate A — sampled command execution

The only gate that catches an invented metric name or monitor ID. Take 5 random dossiers, paste
every `tsuga` command from their Ready-to-run sections into a shell, and confirm each one parses
and returns a response. Empty results (`{"logs":[]}`, `{"series":[]}`) pass; a CLI or API error
does not.

```bash
OUT=./skills/knowledge-company/references
find "$OUT"/teams/*/services/*/SERVICE_KNOWLEDGE.md \
  | awk 'BEGIN{srand()} {print rand()"\t"$0}' | sort -n | cut -f2- | head -5 \
  | while read -r f; do
      echo "=== $f ==="
      awk '/^## Ready-to-run/,/^## Golden signals/' "$f" \
        | awk '/^```bash$/{flag=1;next}/^```$/{flag=0}flag'
    done
```

A mistyped `tsuga` command prints nothing at all on stdout, so judge by exit status and stderr,
not by an empty screen.

## Gate B — aggregation body sanity

Aggregation heredocs have the most places to go wrong. Spot-check 3:

```bash
grep -lr "tsuga aggregation" "$OUT"/teams \
  | awk 'BEGIN{srand()} {print rand()"\t"$0}' | sort -n | cut -f2- | head -3 \
  | while read -r f; do echo "=== $f ==="; awk '/<<JSON$/,/^JSON$/' "$f" | head -50; done
```

Each body must have `"timeRange"` in Unix seconds (`$FROM` / `$TO`, never a relative string), a
`"dataSource"` of `"logs"`, `"traces"`, `"metrics"` or `"rum"` (never `"spans"`), `"groupBy"` /
`"formula"` / `"aggregationWindow"` at body level rather than inside a query item, and a
`"field"` on every aggregate when the data source is `"metrics"`.

## Gate C — team cross-link

Every service dossier must point back at its team dossier:

```bash
find "$OUT/teams" -name SERVICE_KNOWLEDGE.md -path '*/services/*' \
  | while read -r f; do grep -q "TEAM_KNOWLEDGE.md" "$f" || echo "MISSING team cross-link in $f"; done
```

**Pass:** no output.

Informational alongside it — services named in the top-level symptom table with no dossier of
their own. Some legitimately have none:

```bash
grep -oE '`[a-z][a-z0-9-]+`' "$OUT/COMPANY_TELEMETRY_KNOWLEDGE.md" | sort -u > /tmp/svc-named.txt
find "$OUT/teams" -name SERVICE_KNOWLEDGE.md -path '*/services/*' \
  | awk -F/ '{print "`" $(NF-1) "`"}' | sort -u > /tmp/svc-have.txt
comm -23 /tmp/svc-named.txt /tmp/svc-have.txt | head
```

## Gate D — human eyeball

No automated substitute. Open 5 random dossiers and read them end to end:

- **Quick context** — does the framing match what the live log probe shows, or is it template filler?
- **Golden signals** — are the thresholds pulled from real monitor definitions or invented?
- **Log shape** — do the pattern strings read like real log lines?
- **Incident shapes** — do the cited paths exist? (`ls skills/incident-history/references/incidents/INC-xxxx/SUMMARY.md`)
- **Confidence note** — tiered and specific, or one generic paragraph?

Length is a weak proxy worth a glance: under 120 lines usually means the service did not merit a
dossier, over 450 means it is padded.

```bash
find "$OUT"/teams/*/services/*/SERVICE_KNOWLEDGE.md -exec wc -l {} + \
  | awk '$2 != "total" && ($1<120 || $1>450)'
```

## When a gate fails

Do not hand-edit the output. The tree is regenerable; a patched file is clobbered on the next
rebuild and the root cause ships to the next fleet.

| Failure | Root cause to fix |
|---|---|
| Missing sections | `SERVICE_KNOWLEDGE_TEMPLATE.md`, then regenerate those services |
| Forbidden tokens | `CLI_TRANSLATION.md` or the contract reference in `SUBAGENT_PROMPT.md` |
| Gate A / Gate B | the command shapes in `CLI_TRANSLATION.md` and the template; re-check them against `tsuga <command> --help` before regenerating |
| Gate C | the cross-link line in `SERVICE_KNOWLEDGE_TEMPLATE.md` |

Regenerate the affected batch, then re-run every gate. Do not ship a partial pass.
