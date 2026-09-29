---
name: gh
description: "Establishes what changed and what actually shipped, using the GitHub CLI for workflow runs, pull requests, commits, releases, deployments and issues, paired with local git for exact file diffs. Use to correlate an incident window with recent changes, find which pull requests touched a service path, verify whether a merged pull request reached an environment, inspect a commit or its diff, list releases and tags, check a workflow run or a failed job's logs, and establish what shipped before a regression started. Read-only by default: any mutation needs explicit confirmation."
---

# GitHub CLI (gh)

Answer "what changed and what shipped." Pair with local `git` for exact file diffs.

Smoke-test access first: `gh auth status`. It must report a logged-in account before anything below is worth running.

Flags and JSON field lists come from `gh <command> --help`. What follows is which call answers which question.

## What shipped in the incident window

```bash
# Workflow runs created in the window
gh run list -R OWNER/REPO --created ">=<incident-start>" --limit 200 --json name,conclusion,createdAt,headSha,url,event
# Narrow to the deploy workflow on the branch that actually ships
gh run list -R OWNER/REPO --workflow deploy.yml --branch main --limit 200 --json conclusion,createdAt,headSha,url
# PRs merged in the window. `gh search prs` has no mergedAt field — on a merged PR,
# closedAt IS the merge time.
gh search prs --repo OWNER/REPO --merged --merged-at "<incident-start>..<incident-end>" --limit 200 \
  --json number,title,closedAt,url,author
# Deployments — the only artifact that answers "did it actually roll out"
gh api repos/OWNER/REPO/deployments --paginate --jq '.[] | {id, environment, created_at, sha, ref}'
gh api repos/OWNER/REPO/deployments/<id>/statuses --jq '.[] | {state, created_at, description}'
gh release list -R OWNER/REPO --limit 200 --json tagName,publishedAt,isLatest
```

Date flags accept `>=`, `<=` and `A..B` ranges, with or without a time part — `--help` prints only "date".

Every `gh` list and search command pages, and truncates by recency rather than by filter: without an
explicit `--limit` the deploy that caused the incident falls off the page and the window reads as quiet.
Defaults are 20 for `gh run list`, 30 for `gh search prs`, `gh release list` and `gh pr list`.

## Which PRs touched a service path

Issue search does not index changed files, so a path filter has to go through the commits endpoint, which does. `gh pr list` cannot express a path filter at all.

```bash
gh api "repos/OWNER/REPO/commits?path=path/to/service&since=<incident-start>&until=<incident-end>" \
  --paginate --jq '.[].sha' \
  | while read -r sha; do gh api "repos/OWNER/REPO/commits/$sha/pulls" --jq '.[] | "\(.number) \(.title)"'; done \
  | sort -u
```

The window here is commit-authored date, not merge date: widen it, then confirm the merge time per PR below.

`--paginate` emits one JSON array per page, so `--jq '.[]'` is right. A whole-result jq (`length`, `sort_by`) needs `--slurp`, which `gh api` rejects alongside `--jq` — pipe to `jq` instead: `gh api … --paginate --slurp | jq 'add | length'`.

## Drilling into one candidate

```bash
gh pr view <number> -R OWNER/REPO --json files,title,body,mergedAt,author,url
gh pr diff <number> -R OWNER/REPO
gh pr list -R OWNER/REPO --state merged --search "<sha>"    # which PR introduced a SHA
gh run view <run-id> -R OWNER/REPO --log-failed             # failed steps only
gh api repos/OWNER/REPO/commits/<sha> --jq '.files[] | .filename'
```

## Local git pairing

`gh` = remote history. `git` = exact file content in the incident window.

```bash
git log --since="<incident-start>" --until="<incident-end>" --oneline --decorate
git show <sha> --stat
git diff <old_sha>..<new_sha> -- path/to/config path/to/helm
git blame path/to/file.yaml
```

If `git status` is dirty, the working tree is NOT a safe proxy for the incident window. Warn before drawing conclusions.

## Anti-patterns

- `merged` ≠ `deployed`. Check workflow run / release / deployment status.
- `main` ≠ `prod` on every repo. Some deploy from a release branch or a tagged commit.
- Green CI proves build + unit tests, not that the change works under real traffic.
- Green run ≠ change in prod. Red run ≠ nothing rolled out. Check per-env deploy status.
- Dependabot / bot commits are still real changes; they cause incidents.
- Auto-merged PR by someone on vacation ≠ red flag. Don't over-index on authorship.

## Output style

Every change candidate includes:

- merge timestamp AND deploy timestamp
- artifact type (PR / run / release / commit)
- concrete identifier (PR #, SHA, run URL, tag)
- touched surface (file paths or service)
- deploy status (`deployed` | `merged only` | `unknown`)

Citation shape: `PR #<number> merged <merge-ts>, deployed via run #<run-id> at <deploy-ts>, touched <path> [evidence: gh_pr, gh_run]`.
