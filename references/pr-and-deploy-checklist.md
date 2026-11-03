# Commits, push, pre-deploy and the reports (Phase 8 to 10)

## Contents

1. Commit plan
2. Branch and history rules
3. Push rules (ask first)
4. Pre-deploy checklist (ops and DB)
5. Deploy and post-deploy verification
6. Rollback
7. Residual-risk report template
8. Final report template
9. Secret handoff template

## 1. Commit plan

Group commits by theme. Each commit must leave the project lintable and should be revertable on its own. A reasonable order for a PHP 8 upgrade (the reference run's order, generalised):

| # | Theme | Example subject (conventional-commit form; use the project's own style) |
|---|---|---|
| 1 | Runtime and build base: image tag, Dockerfile, composer constraint | `feat(php84): move runtime to php 8.4.x image` |
| 2 | Framework swap (if chosen): move app files out, pin fork, replace core | `refactor(php84): move app config out of system` then `feat(php84): swap core to fork` |
| 3 | Error policy and CI lint gate | `chore(php84): report all errors to stderr and add lint gate` |
| 4 | Mechanical PHP 8 fixes (per theme or per module) | `fix(php84): null input into json_decode` |
| 5 | Subclass and log fixes for the new core | `fix(php84): log subclass delegates to core` |
| 6 | Dependency fixes (driver versions, removed packages) | `fix(php84): drop unused mongo adapter packages` |
| 7 | Dead-feature removal, one feature per commit | `fix(php84): remove dead chat detail links` |
| 8 | Auth-gap fixes, one group per commit | `fix(php84): require login for widget and monitor controllers` |
| 9 | Notes updates (or inline in the commits above) | `docs(php84): update upgrade notes for removed features` |

Rules:

- Subject line in the project's style (check `git log`). With no house style, use the imperative mood. Keep it under about 72 characters.
- Body: the reason, and any DB or ops step. Not a list of every file.
- A commit that removes a feature and the notes about it may be one commit or two (the reference run used two).
- Never commit secrets, `.env` files with values, or generated files you do not need to review.
- Check `git status` and `git diff --cached --stat` before each commit. Stage specific files; do not `git add -A` over unrelated work.

## 2. Branch and history rules

- Work on the branch the user named. If none was named, create `upgrade/php8` (or the project's convention) from the base the user confirmed, and say so.
- Do not force-push. Do not rebase or amend commits that were already pushed.
- Do not rewrite history to remove a secret. Report it instead.
- Tag the baseline before the first change (`git tag <baseline-tag>` locally; push the tag only on instruction).

## 3. Push rules (ask first)

A push is outward-facing. Before any push:

1. Ask the user for explicit permission, naming the remote and the branch.
2. Read the CI configuration for that branch. In the reference run, the build and deploy jobs for the deploy branch run on push with no manual gate. A push to that branch deploys.
3. Confirm the image tag and container name the deploy will use (below).

Approval given for one push does not cover the next.

## 4. Pre-deploy checklist (ops and DB)

Hand this to the person who runs the deploy and the database. The reference run's order, generalised. Do not run any step against production without the owner's approval.

1. **Backup the database** before any data change. Confirm the backup can be restored.
2. **Switch off dead entry points in the data**, before the code that removes their views is deployed: deactivate the widget documents that name removed views (keep their `_id`s in the notes), hide menu items and permissions that point at removed routes, disable scheduled tasks that call removed commands.
3. **Clear the cache that holds those lists** (for example the widget list cache with its TTL). Do not use an admin "clear cache" that deletes log files.
4. **Session impact.** If the session format or driver changed, every user will be logged out once. Tell users, and plan the timing.
5. **Other caches.** If the cache key format changed (CI output cache, Redis hashes, Memcached), flush the affected caches at cut-over. Record which.
6. **Image tag.** The image must carry an immutable tag tied to the commit (for example `php84-<short-sha>`), not a moving tag such as `:dev`. Otherwise a re-run of an old pipeline redeploys an old image.
7. **Container name and ports.** Names and host ports must be unique per environment. Check before any `docker rm -f`. A reused name removes another environment's container.
8. **Baked-in configuration.** Values inside `.env` files baked into the image need a rebuild to change. List them (names only).
9. **Extensions.** The image has every extension the code calls (`php -m` output saved), and nothing the code does not call without a recorded reason.
10. **Destructive data steps** (unset fields, drop collections, delete rows) are not part of this deploy. They run only after the code is live, the callers are confirmed gone, and the owner approves. Record them as a separate follow-up.

## 5. Deploy and post-deploy verification

Deploy the built image. Then, in this order:

1. Confirm the running container uses the expected image, before you read any log:

```bash
docker inspect <container> --format '{{.Config.Image}}'
```

2. Check the home page and the sign-in page: status 200 and no PHP notices in the body.
3. Log in with a test account on staging or with the owner's approval on production. Make one authenticated JSON request and check the body starts with JSON.
4. Read the container log for `Deprecated`, `Warning`, `Fatal`, `TypeError`, after a short warm-up, because some errors appear only on use.
5. Check the scheduled jobs ran at their next time (or run one by hand, if the owner approves).

Do not report "deployed OK" unless steps 1 to 4 were done and their output is in the report.

## 6. Rollback

Record before deploy:

- The previous image tag, and the commit it was built from.
- The previous code tag (the baseline tag).
- Whether a rollback needs the package manager to work (Composer). If the build cannot reach its registry, the rollback is the old image, not a rebuild.
- Which data steps are reversible. Dropped data is not reversible: write that down.

## 7. Residual-risk report template

```markdown
## Residual risk

### Verified (command and result)
| Check | Command | Result |
|---|---|---|
| Lint, target PHP | scripts/lint-gate.sh 8.4 <dirs> | GATE PASS: N results |
| Lint, next PHP | scripts/lint-gate.sh 8.5 <dirs> | GATE PASS: N results |
| Lint gate can fail | scripts/lint-gate.sh --negative-control 8.4 | PASSED |
| Hazard sweep F group | scripts/sweep-patterns.sh . | 0 after review |
| Login gate | unauthenticated requests against <env> | 302 x N, 401 x N, 200 x 0 for protected |

### Not verified
| Area | Why not | Risk |
|---|---|---|
| Real data and production database | staging only | ... |
| Mail (SMTP, IMAP) | no test account | ... |
| Excel and CSV with real files | not run | ... |
| Cron jobs under real schedule | not run | ... |
| Oracle or other partner endpoints | no access | ... |
| Per-role permissions | login gate only | ... |

### Follow-ups (not blocking)
| Item | Priority | Why not done now |
|---|---|---|

### Decisions needed from the user
| Question | Options | Recommendation |
|---|---|---|

### Ops actions
| Action | Owner | Detail (no values) |
|---|---|---|
| Rotate secret | ops | path and key name; in git history: yes or no |
```

## 8. Final report template

Based on the bundled playbook's handover report format (`references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md`, section 14). Keep it factual; every number has its command.

```markdown
# Upgrade report: <app>

## Scope
- From: CI <version>, PHP <version>. To: <core>, PHP <target> (lint also on <next>).
- Branch: <name>. Baseline tag: <tag>. Base commit: <sha>.

## Work by phase
| Phase | Commits | Summary |
|---|---|---|

## Verified
| Item | Command | Result |
|---|---|---|

## Not verified
| Item | Reason |
|---|---|

## Remaining debt
| Item | Priority | Why not done |
|---|---|---|

## Decisions needed
| Question | Options |
|---|---|

## Rollback
- Tag: <tag>. Image: <previous image>. Condition: <what the rollback needs>.
```

## 9. Secret handoff template

Use this when a secret is found. Never put a value in it.

```markdown
Subject: Secret rotation needed for <app>

The following secrets are stored in the repository. Please rotate them at their source and update the environments that use them.

| File (repo path) | Key name | In git history | Action |
|---|---|---|---|
| application/config/<file> | <key name> | yes / no | rotate; move to environment or ignored file |

We have not rewritten git history. Rotating the credentials is what makes the exposure harmless.
```
