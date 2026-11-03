---
name: php-ci-upgrade
description: Run a legacy PHP / CodeIgniter 3 upgrade end to end, to PHP 8.4
  with 8.5 readiness, optionally swapping the CI 3.1.x core for the
  hoangkim28/codeigniter fork. Use it whenever the user wants to upgrade,
  migrate or modernise a PHP app to PHP 8.x; move a CodeIgniter 3 app to a newer
  core; fix PHP 8 deprecations, fatals or TypeErrors after a PHP bump; bump a
  PHP Docker image; audit a legacy PHP app for PHP 8 readiness or check where an
  upgrade stands; remove dead features before an upgrade; or review login gating
  of old controllers. Use it even for one slice, such as a lint gate or one
  error, because the phase order and its traps decide whether the upgrade works.
  Trigger phrases include "nâng cấp PHP 8.4", "nâng PHP lên 8.5", "migrate PHP",
  "upgrade CodeIgniter 3", "fork hoangkim28", "kiểm tra hiện trạng nâng cấp",
  "sửa deprecation sau khi nâng PHP", "lỗi fatal sau khi upgrade", "đổi image
  php docker", "gỡ tính năng chết", "kiểm tra đăng nhập các controller", "imap
  không chạy sau khi nâng".
disable-model-invocation: true
metadata:
  opencode/autoinvoke: false
---

# PHP + CodeIgniter 3 upgrade

This skill runs an upgrade the way one real project ran it (provenance: namabank, branch `dev-php8427`, 22 commits, PHP 8.4.27, CI 3.1.9 to the `hoangkim28/codeigniter` fork v0.2.1). The order, gates and lessons below come from that run. Generic enough for any CodeIgniter 3 app, and mostly applicable to other legacy PHP.

Lint passing is not the goal. Lint catches syntax and compile-time deprecations. It misses NULL into internal functions, removed-but-parseable calls, runtime-only behaviour and missing extensions. The phases below are built around that gap.

## Step 0: read the team's upgrade docs first (bundled copy)

The team's upgrade docs are bundled in `references/upgrade-docs/`. They are the default source. Read them in this order:

1. `references/upgrade-docs/README.md` first. It is the index: versions, paths, and which file each role reads.
2. The playbook, `references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md`, then the lessons files: `LESSONS_HANMIR_PHP84.md` (core kept on CI 3.1.x and patched in place) and `LESSONS_NAMABANK_PHP84.md` (core swapped to the fork).
3. `UPGRADE_PHP.md` for the version tables. Read `UPGRADE_FROM_3.1.13.md` only when you swap the core, and `UPGRADE_FROM_2.2.6.md` only for a CI 2.2.6 source. `COMPARE_JACCS_HANMIR.md` compares two reference codebases; read it only for a current-state comparison. Skip the rest unless a file points to it.

Then ask the user once whether the team has a newer docs folder. If it has, prefer it when its files differ from the bundled copy or are newer (compare modified dates and sizes), and tell the user which copy you used. Without a newer folder, use the bundled copy as it is.

The playbook and lessons are more specific than this skill. Where they disagree with this skill, the playbook wins for that project; tell the user about the disagreement.

The rest of this skill holds the same material, generalised. Use it for the phase order, gates and checklists.

Paths in this skill that start with `references/` or `scripts/` are relative to this skill's folder (the one holding this SKILL.md). Commands run from the project root, so call the scripts by absolute path (see Scripts).

## Roles

Work in roles, whether you are one agent or many. These are roles, not agent names: map each one to whatever agents or sessions you have, or play all of them yourself.

| Role | Does | Output |
|---|---|---|
| Coordinator (you) | Sequences phases, asks the user, integrates the results, runs the final checks | Phase status, decisions, final report |
| Researcher (read-only) | Phase 0 and 1: audit, inventory, status table, plan | Status table with file:line evidence |
| Implementor | One themed change at a time, with disjoint file ownership | Commits, lint output, notes |
| Challenger (optional) | Pressure-tests decisions before a delete, a swap or a deploy | Objections with evidence |

Alone: play the roles in order, and write the audit to a file before you change code. With other agents: hand a role over with a template from `references/delegation-prompts.md`; handing over is optional. Either way, rerun the gate and check `git status` yourself before you repeat a claim, whether another agent made it or an earlier step of yours did.

## Working agreements

These come from the reference run. They are not optional.

- **Ask before anything destructive or outward-facing**: deleting tracked files, `git rm`, pushing (a push to a deploy branch can trigger a deploy), force-push, rewriting history, changing values that a partner depends on (callback URLs, JWT `iss`, IDs). Approval for one step does not cover the next. Before deleting, look at the target: read it, grep its callers.
- **Never print secret values.** Report file paths and key names only. Grep with `-o` on the key name, never on the value. Do not `cat` `.env*` or config files that hold credentials.
- **Secrets already in git**: list them (path and key name) for ops to rotate. Do not rewrite history to hide them.
- **Parallel implementors need disjoint file ownership.** No two implementors (agents, sessions or people) edit the same file.
- **Commits are themed**: one theme per commit (see Phase 9), each one lintable on its own. Notes go in the same commit or the commit right after the change.
- **Verify before you repeat a claim.** Rerun the lint gate, `git status`, `git diff --stat`. Read a sample before counting a grep hit as a bug.
- **Do not change business logic.** Compatibility fixes only. Log business bugs in the report.
- **Do not touch production.** Staging or a local container only. Check the running image before you read its logs.
- **Say what was not tested.** Static checks and smoke tests are not a runtime sign-off.
- **Reply in the user's language.** Keep code identifiers, commands and paths unchanged, and write commit messages and notes in the language the project already uses.

## Decision points

Decide these in Phase 0 and record them. Ask the user where the "ask when" column applies.

| Decision | Default | Ask when |
|---|---|---|
| Target PHP | 8.4 minimum, lint clean on 8.5 too | The runtime or a required package cannot run on 8.5 |
| Core | Swap to the fork when the app runs unpatched CI 3.1.x. Patch in place when the core is heavily patched and the swap would be a rewrite | Core is patched, or the team has not accepted the fork's behaviour changes |
| Fork pin | Pin an exact commit or tag, never a branch (`develop` had one commit and no history as of 2026-10) | Always confirm with the fork owner what the `3.4.5` label means |
| Dead features | Remove when no reachable caller and no live DB dependency | Always, with the candidate list (Phase 5) |
| Auth gap | Add the login gate to every endpoint behind a session. Leave public login pages and secret-authenticated webhooks | Any endpoint you cannot classify, and every cron-style endpoint |
| `composer.lock` | Commit it (reproducible builds; the bundled playbook requires it, section 6) | The project deliberately ignores it |
| Extension install | Install only when you found a caller in code | Never install for "maybe later" |
| Push and deploy | Never without an explicit instruction | Every time |

## Workflow

Each phase has an exit criterion. Do not start the next phase until the current one meets its criterion, unless the user says otherwise. Phases 2 to 4 can run in parallel only when their file sets are disjoint.

### Phase 0. Intake (no edits)

1. Confirm: repo path, base branch, target branch name (default `upgrade/php8`, or the project's own convention), target PHP, core decision, whether a deploy follows, and what "done" means for this run (audit only, or the full upgrade).
2. Check the tree: `git status --porcelain` must be empty and `git branch --show-current` must be the branch you expect. A dirty tree: stop and ask. Do not stash the user's work without asking.
3. Check the runtime truth, not the image name: `docker run --rm php:<target>-cli php -v` for the target, and `docker inspect` or `docker run --rm <prod-image> php -v; php -m` if the production image is available. One project ran PHP 8-only code under an image named `php7-*`.
4. No PHP on the host is normal. Lint and run everything through `php:<version>-cli` containers. Pull the image only if it is missing. Without Docker, use a host PHP of the exact target version if there is one, and say so in the intake note: `scripts/lint-gate.sh` needs Docker, `scripts/sweep-patterns.sh` does not.
5. Record the decisions from the table above.

**Exit:** a 5-to-10-line intake note (repo, branch, base commit, targets, runtime facts, decisions). The user has confirmed any ambiguity.

### Phase 1. Read-only audit (Researcher)

1. Work through `references/audit-checklist.md`: the seven inventory items, then the checks per area.
2. Run `scripts/sweep-patterns.sh <project>` and read the samples. Run `scripts/lint-gate.sh <version> <dirs>` at the current runtime and at the target. Filter false positives and say which filter you applied.
3. Produce the status table: Done, Partial, Not done, Unclear. Every row has evidence: `file:line` or the command and its result. Anything you cannot verify is **Unclear**, with the command that would settle it. Never guess.
4. Save the audit in the project's notes location (for example, an upgrade notes file under `docs/`). Ask before creating a new file.

**Exit:** the status table is saved and the user has read the plan derived from it.

### Phase 2. Confirmed fatals first

1. Fix only what crashes on the target: reversed `implode`, removed functions (`mysql_*`, `ereg*`, `split`, `each`, `create_function`, `money_format`, `get_magic_quotes_gpc`, `mcrypt_*`), parse errors (`$s{0}`, `(real)`, `assert('...')`), `$HTTP_RAW_POST_DATA`. Patterns and fixes: `references/php84-85-patterns.md`.
2. Guard the false positives: `mcrypt_*` and `create_function` inside vendored code behind `function_exists` or `version_compare` do not run on PHP 8. Read the surrounding code before you count a hit.
3. Lint is not enough after this phase. Run one request through the app (Phase 7 gives the smoke list), because NULL-into-internal errors only show at runtime.
4. Keep the app's own files that live inside `system/` safe before you touch the framework (Phase 2b and `references/ci3-fork-swap.md`).

**Exit:** the sweep's F group is 0 after reading the samples, and the lint gate passes at the target version.

### Phase 2b. Framework swap (only if decided in Phase 0)

1. Run the pre-checks in `references/ci3-fork-swap.md`: `diff -rq` against the upstream tag of the same CI version, and list every `Only in ...system...` file. Those are app files. Move them out first (example: a JSON config file moved to `application/config/` and read through `APPPATH`).
2. Pin the fork by commit or tag. Replace `system/` in one commit, then fix the subclass constructors, the session driver, the log subclass and the entry points.
3. Commit the move, then the swap, then the subclass fixes, as separate commits.

**Exit:** the app boots on the target PHP with the new core, and the smoke list in `references/ci3-fork-swap.md` has been run, or the items not run are written down as residual risk.

### Phase 3. Error reporting and infrastructure

1. Make errors reach the logs and stay off the screen in production. Find every place that sets `error_reporting` or `display_errors`: image ini, `index.php`, the env bootstrap, `.htaccess`, and any `ini_set`. Make them agree. Hiding deprecations in one place is not enough, because another place overrides it (one project found three).
2. Check mod_php against php-fpm. `php_value` and `php_flag` in `.htaccess` are valid only under mod_php. Under php-fpm they cause HTTP 500.
3. Do not remove `SetEnv CI_ENV` if code writes it. An admin page that rewrites `.htaccess` depends on that line, and removing it silently moves the app to production.
4. Extensions: `imap` left core PECL in 8.4, `ftp` is absent from the official images, `soap` needs its own install. Grep the callers before you install anything. An extension with no caller is debt, not safety.
5. Pin `ext-mongodb` to the version that matches the MongoDB server in use, and use the same version in dev and prod.

Details and snippets: `references/infra-and-docker.md`.

**Exit:** one error-configuration story that every grep agrees with, a Dockerfile that builds on the target, and `php -m` in the built image lists every extension that the code calls (sweep group R, `ext_*`).

### Phase 4. Mechanical sweeps (lint-invisible)

1. Work by theme, one theme per commit: NULL into internal functions (`json_decode($this->input->post(...))` becomes `... ?? ''`), `count()` on NULL (guard only what can be NULL), `${var}` in PHP strings, `utf8_encode`, deprecated casts, `$http_response_header`, `is_resource()` on IMAP and cURL objects, `curl_close`, `E_STRICT`, implicit nullable parameters, `fputcsv` without `$escape`, dynamic properties. Each has a grep and a before/after in `references/php84-85-patterns.md`.
2. Large themes go module by module, one commit per module, so review stays possible (a single 132-file commit was the exception, not the rule).
3. Record the sweep counts before and after each commit.

**Exit:** the sweep's F and D groups are 0 after you have read the samples, the R group is reviewed and each item recorded as fixed, accepted or open, and the lint gate passes.

### Phase 5. Dead-feature removal instead of porting

1. Decide per feature with evidence, not by name. Check code callers, routes, views, JavaScript, cron and scheduler files, CI, and the database-side documents (widgets, menus, permissions, scheduled tasks). `references/dead-feature-removal.md` has the commands.
2. Port only what has a live caller. Remove what has none. External login, a chat module, map views and a test harness were removed this way.
3. Present the candidate table (feature, files, callers found, DB dependency, proposed action) and get the user's confirmation before any `git rm`.
4. Write the DB-side steps into the pre-deploy checklist. The repo cannot change database content.

**Exit:** each removed feature has a grep showing zero callers, each DB dependency has an entry in the pre-deploy checklist, and the user approved the list.

### Phase 6. Auth-gap audit

1. Enumerate every controller and every public method reachable by URL. Classify each endpoint: page or API behind login, public login page, secret-authenticated webhook, cron or CLI-only, internal self-call, unknown.
2. Add the login gate to the first group. Leave the login page and the webhooks (check their secret comparison and where the secret lives). Make the cron group CLI-only where possible. Stop and ask about the rest.
3. Make helpers `private` or `protected`. Every public method is a URL in CodeIgniter.
4. Verify with an unauthenticated request to each endpoint against staging or a local container: expect 302, 401 or 403, never 200 for a protected endpoint.

Method and fix pattern: `references/security-sweep.md`.

**Exit:** every endpoint has a classification. Anything left as unknown is accepted by the user and written down as residual risk.

### Phase 7. Lint gate, CI stage and smoke test

1. Add a lint stage to CI that reads the output, not the exit code. `php -l` exits 0 for files that only produce `Deprecated`. The gate must run with `short_open_tag` 0 and 1 (`references/infra-and-docker.md` has the job).
2. Run `scripts/lint-gate.sh <target> <dirs>`. Run `scripts/lint-gate.sh --negative-control <target>` once, and keep its output as evidence that the gate can fail.
3. Run `composer validate`, and `composer audit` where the lock file exists.
4. Smoke test on staging or a local container with the real services (MongoDB, Memcached, Redis and so on, as the app needs them). Minimum list: home page, login page, login and logout, one authenticated JSON API with no PHP warnings in the body, one export, one upload, one cron run, one mail send if mail is in scope. The full list is in `references/ci3-fork-swap.md` and `references/pr-and-deploy-checklist.md`.

**Exit:** the gate passes at the target, its negative control output is saved, and the smoke results are reported with what was actually run.

### Phase 8. Docs in the same change

1. Each behaviour change gets a note in the project's upgrade notes: what changed, what the database or ops must do, what was not tested. The rule: a note lands with the commit that causes the change, or in the commit right after it.
2. Check that the notes match the code. Grep the names they mention.

**Exit:** every behaviour change has a note, and the notes match the code.

### Phase 9. Commit, branch and push (ask first)

1. Commit by theme, in the project's existing message style (read `git log --oneline -20`). The reference run used short imperative subjects such as `Remove dead chat detail links`; with no house style, `fix(php84): ...` is a fine default. Never rewrite history, never force-push.
2. Push only on the user's explicit instruction. Read the CI rules first: a push to a deploy branch can deploy automatically (a deploy job on the deploy branch ran on push with no manual gate).
3. Hand ops the pre-deploy checklist (backup, dead widgets and menus off, caches, container names and ports, image tag by commit SHA). Details: `references/pr-and-deploy-checklist.md`.
4. After a deploy, confirm the running image before reading any log.

**Exit:** the commit list is ready. The push, if any, happened on instruction, and the ops checklist is delivered.

### Phase 10. Residual-risk report

1. Write the report with the template in `references/pr-and-deploy-checklist.md`. Split it into what was verified (command and output), what was not verified (and why), follow-ups, and decisions still needed from the user.
2. State plainly what runtime coverage is missing. Static checks do not cover real data, the production database cluster, SMTP and IMAP, Excel with real files, cron jobs under load, or Oracle.

**Exit:** the report is delivered. The user decides what happens next.

## Reference map

Read a reference when its phase starts, not before.

| File | Read when |
|---|---|
| `references/audit-checklist.md` | Phase 0 and 1: inventory items, checks per area, status-table template |
| `references/php84-85-patterns.md` | Phase 2 and 4: each hazard, its grep, its before and after |
| `references/ci3-fork-swap.md` | Phase 2b: swapping `system/` for the fork, behaviour changes, smoke list |
| `references/infra-and-docker.md` | Phase 3 and 7: Dockerfile, ini, `.htaccess`, extensions, CI lint job |
| `references/security-sweep.md` | Phase 6: login-gate discovery, classification, fix pattern, secrets |
| `references/dead-feature-removal.md` | Phase 5: caller checks, DB dependencies, removal order |
| `references/pr-and-deploy-checklist.md` | Phase 8 to 10: commit plan, push rules, pre-deploy checklist, report templates |
| `references/delegation-prompts.md` | When another agent or session takes a role. Working alone, use the templates as checklists |
| `references/upgrade-docs/README.md` (bundled) | Step 0, first: the index, the `3.4.5` fork warning, and which file each role reads |
| `references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md` (bundled) | Step 0 and every phase: the playbook's order and rules, acceptance criteria per phase (section 10), handover report (section 14). Wins over this skill for its project |
| `references/upgrade-docs/LESSONS_HANMIR_PHP84.md` (bundled) | Step 0, and Phases 2 to 4 when the core stays on CI 3.1.x and is patched in place: lint traps, Mongo session driver, deploy traps |
| `references/upgrade-docs/LESSONS_NAMABANK_PHP84.md` (bundled) | Step 0, and Phases 2b to 6 when the core is swapped to the fork: swap, dead features, login-gate audit, database before deploy |
| `references/upgrade-docs/UPGRADE_PHP.md` (bundled) | Phases 2 and 4: PHP breaking changes by version, extension notes, version tables |
| `references/upgrade-docs/UPGRADE_FROM_3.1.13.md` (bundled) | Phase 2b only, when the source is CI 3.1.x and the core is swapped |
| `references/upgrade-docs/UPGRADE_FROM_2.2.6.md` (bundled) | Phase 2b only, when the source is CI 2.2.6 (two major versions; see `ci3-fork-swap.md` section 12) |
| `references/upgrade-docs/COMPARE_JACCS_HANMIR.md` (bundled) | Phase 1, only for a current-state comparison with the two reference codebases. Skip for other projects |

`references/upgrade-docs/` is a copy of the team's docs; each copied file's first line gives its copy date. The other references are this skill's own distilled versions of the same material. On a conflict, the bundled playbook and lessons win for details; this skill wins for the workflow order.

## Scripts

Run from the project root, calling the scripts by absolute path. `lint-gate.sh` needs Docker and either a local `php:<version>-cli` image or network access to pull one; `sweep-patterns.sh` needs only bash, grep and awk. Neither writes into the repo.

```bash
# Lint gate: reads php -l output, passes only when every line is "No syntax errors detected"
S="<skill-dir>/scripts"   # absolute path of this skill's scripts/ folder, wherever the skill is installed
$S/lint-gate.sh 8.4 application index.php     # add the other PHP paths that exist; a missing path fails the gate
$S/lint-gate.sh --negative-control 8.4        # proves the gate can fail

# Hazard sweep: counts per pattern with samples; exit 1 when F-group hits exist
$S/sweep-patterns.sh --samples 3 .
$S/sweep-patterns.sh --full --include-third-party .
```

Read the sweep's samples before you trust its counts. Comment lines and JavaScript template literals are dropped automatically. Hits inside HTML or JavaScript in view files are not PHP, and some hits are real but guarded.

## Gotchas that cost time in practice

- `php -l` exits 0 on `Deprecated`. Gate on output.
- Lint does not see `implode` argument order, `count(NULL)`, `json_decode(NULL)`, `curl_close`, `E_STRICT`, short tags, or missing extensions.
- Deprecations hidden in three places (image ini, `index.php`, env bootstrap). Fixing one leaves the others.
- `.env` and config baked into the image: a value change needs a rebuild.
- An admin "clear cache" button that deletes the log directory removes the evidence you need after a deploy.
- Removing a widget's view while the widget document is active breaks every page for the cache TTL.
- `composer update` at build time with `--ignore-platform-req=php` and `--no-security-blocking` means nobody knows which versions run. Commit the lock or record the risk.
- Mongo driver major versions and `mongodb/mongodb` must match. Dev and prod must use the same extension version.
- A gate you have never seen fail is not a gate: run the negative control.