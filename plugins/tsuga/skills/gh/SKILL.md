---
name: gh
description: GitHub CLI for inspecting workflow runs, PRs, commits, releases, and deployments. Use to correlate an incident window with what changed, verify whether a merged PR actually deployed, inspect a specific commit, list recent releases, or check workflow run status. Read-only by default.
---

# GitHub CLI (gh)

Answer "what changed and what shipped." Pair with local `git` for exact file diffs.

Authenticated from `GH_TOKEN` at container start. Smoke-test: `gh auth status`.

## Commands

### Workflow runs

```bash
gh run list -R owner/repo --created ">=2026-04-20T14:00" --json name,status,conclusion,createdAt,headSha,url,event
gh run list -R owner/repo --workflow deploy.yml --branch main --limit 20 --json conclusion,createdAt,headSha,url
gh run view <run-id> -R owner/repo --log
gh run view <run-id> -R owner/repo --json jobs
```

Green run ≠ change in prod. Red run ≠ nothing rolled out. Check per-env deploy status.

### Pull requests

```bash
# PRs merged in a window
gh search prs --repo owner/repo --merged --merged-at "2026-04-20..2026-04-21" --json number,title,mergedAt,url,author
# PRs touching a path
gh search prs --repo owner/repo --merged -- "path/to/service"
# PR matching a SHA
gh pr list -R owner/repo --state merged --search "<sha>" --json number,title,mergedAt,url
# PR details
gh pr view <number> -R owner/repo --json files,title,body,mergedAt,author,url
gh pr diff <number> -R owner/repo
```

### Releases

```bash
gh release list -R owner/repo --limit 10 --json tagName,name,publishedAt,isLatest
gh release view <tag> -R owner/repo --json body,tagName,publishedAt,assets
```

### Commits

```bash
gh api repos/owner/repo/commits --jq '.[] | {sha, author: .commit.author.name, date: .commit.author.date, message: .commit.message | split("\n")[0]}' --paginate | head -40
gh api repos/owner/repo/commits/<sha> --jq '.files[] | .filename'
```

### Deployments

```bash
gh api repos/owner/repo/deployments --paginate --jq '.[] | {id, environment, created_at, sha, ref}' | head -20
gh api repos/owner/repo/deployments/<id>/statuses --jq '.[] | {state, created_at, description}'
```

### Issues

```bash
gh issue list -R owner/repo --search "<keyword> in:title,body" --state open --json number,title,url,createdAt
gh issue view <number> -R owner/repo --json title,body,comments
```

### Raw API (when flags don't cover the case)

```bash
gh api repos/OWNER/REPO/actions/runs --jq '.workflow_runs[0]'
gh api 'repos/OWNER/REPO/commits?since=2026-04-20T00:00:00Z&until=2026-04-21T00:00:00Z' --paginate
```

## Local git pairing

`gh` = remote history. `git` = exact file content in the incident window.

```bash
git log --since="2026-04-20 09:00" --until="2026-04-20 12:00" --oneline --decorate
git show <sha> --stat
git diff <old_sha>..<new_sha> -- path/to/config path/to/helm
git blame path/to/file.yaml
```

If `git status` is dirty, the working tree is NOT a safe proxy for the incident window. Warn before drawing conclusions.

## Anti-patterns

- `merged` ≠ `deployed`. Check workflow run / release / deployment status.
- `main` ≠ `prod` on every repo. Some deploy from release branch or tagged commit.
- Green CI proves build + unit tests, not that the change works under real traffic.
- Dependabot / bot commits are still real changes; they cause incidents.
- Auto-merged PR by someone on vacation ≠ red flag. Don't over-index on authorship.

## Output style

Every change candidate includes:
- merge timestamp AND deploy timestamp
- artifact type (PR / run / release / commit)
- concrete identifier (PR #, SHA, run URL, tag)
- touched surface (file paths or service)
- deploy status (`deployed` | `merged only` | `unknown`)

Example citation: `PR #4421 merged 2026-04-20T13:45Z, deployed via run #8192 at 14:02Z, touched services/payments/db.py [evidence: gh_pr, gh_run]`.
