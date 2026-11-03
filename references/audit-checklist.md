# Audit checklist (Phase 0 and 1)

Read-only. Nothing in this file edits the project. Output is a status table with evidence.

## Contents

1. Status table template
2. Phase 0 inventory (seven items)
3. Runtime truth
4. Checks per area
5. Filtering rules for grep hits
6. Common mistakes

## 1. Status table template

Every row needs evidence. "Looks fine" is not evidence.

```markdown
| # | Area | Item | Status | Evidence (file:line, or command and result) | Next step |
|---|---|---|---|---|---|
| 1 | Framework | CI_VERSION | Done | system/core/CodeIgniter.php:59 = '3.4.5' | none |
| 2 | Errors | E_ALL in image | Partial | Dockerfile:52 sets E_ALL; index.php:72 still masks E_DEPRECATED | fix index.php |
| 3 | Fatals | implode reversed | Not done | rg output: 2 hits in cronjob/... (after filter, see 5) | Phase 2 |
| 4 | Infra | imap extension | Unclear | no caller found in application/; php -m not run | run php -m; grep callers |
```

Status meanings:

- **Done**: a command proved it. The command and result are in the evidence column.
- **Partial**: some sites are done, some are not. Give both counts.
- **Not done**: a command proved the problem still exists.
- **Unclear**: you could not verify it. Say which command would settle it, and do not count it as done.

## 2. Phase 0 inventory (seven items)

Record all seven in the audit file. Missing items mean the audit is incomplete.

1. **Baseline**: framework version (`CI_VERSION` and the command that printed it), core source (bundled or composer), real PHP runtime (`docker run ... php -v`), extensions in the image (`php -m`), web server (mod_php or php-fpm).
2. **Patched core**: files in `system/` that differ from the upstream tag of the same version, and any app file that sits inside `system/`.
3. **Core extensions**: app classes that extend framework classes (`MY_*` or the project's own prefix) and their constructors.
4. **Packages**: `composer.json` constraints (`php`, every package), whether `composer.lock` and `vendor/` exist, abandoned packages.
5. **Errors found by PHP 8 scan**: counts per group after filtering, each with file:line samples and the fix.
6. **Extensions the code uses but the image lacks**: function prefixes in code against `php -m`.
7. **Not verified**: a list of what the audit could not check, with the reason.

See also: the bundled playbook, section 3.1 (`references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md`), has the same mandatory Phase 0 commands.

Commands for items 1 to 4 (run from the project root, `$APP` = project root, `$UP` = a clean upstream tree of the same CI version, if you have one):

```bash
APP=.
grep -rn "CI_VERSION" "$APP/system/core/CodeIgniter.php" 2>/dev/null
grep -n "system_path\|application_folder\|view_folder" "$APP/index.php"
ls "$APP"/*/index.php 2>/dev/null                 # a second entry point?

# Patched core and app files inside system/
[ -n "${UP:-}" ] && diff -rq "$APP/system" "$UP/system" | head -50
[ -n "${UP:-}" ] && diff -rq "$APP/system" "$UP/system" | grep '^Only in' # app files living in system/

# Bootstrap copied into the app?
ls -la "$APP/application/core/" 2>/dev/null
grep -rn "APPPATH.*CodeIgniter.php\|BASEPATH.*CodeIgniter.php" "$APP/index.php" "$APP"/*/index.php 2>/dev/null

# Core extensions
grep -n "subclass_prefix" "$APP/application/config/config.php"
ls "$APP/application/core" "$APP/application/hooks" 2>/dev/null
grep -rnE "class[[:space:]]+[A-Za-z_]*(Hooks|URI|Utf8|Security|Input|Log|Loader|Router|Output|Session)\b" "$APP/application" 2>/dev/null

# Packages
cat "$APP/composer.json"
ls "$APP/composer.lock" "$APP/vendor" 2>/dev/null || echo "NO LOCK OR VENDOR"
ls "$APP/application/third_party" 2>/dev/null     # copied-in libraries
```

## 3. Runtime truth

Do not trust image names or `composer.json` alone. Check what the running container does.

```bash
# Target runtime (lint and smoke both use this)
docker run --rm php:8.4-cli php -v
docker run --rm php:8.4-cli php -m

# Production image, if you have access (never guess the tag)
docker inspect <container> --format '{{.Config.Image}}'
docker run --rm <prod-image> php -v
docker run --rm <prod-image> php -m
```

Record: PHP version, the extensions the code needs and their presence, whether `ftp`, `imap`, `soap`, `mongodb`, `memcached`, `redis` are loaded.

Known facts to verify, not assume:

- The official `php:*-cli` image has no `ftp` extension (checked on php:8.4-cli).
- `imap` is no longer built into core from PHP 8.4. Install it with a PECL-capable installer.
- An image tagged `php7-*` can run PHP 8-only code (seen in one project). Check `php -v`.

## 4. Checks per area

| Area | What to check | How | Typical finding |
|---|---|---|---|
| Framework | CI version, bundled or composer, patched core | Section 2 commands | `system/` patched in place; app files inside `system/` |
| Bootstrap | App copy of `CodeIgniter.php` | `ls application/core` | 500+ line copy with dead PHP-5.4 blocks |
| Core extensions | Constructors of subclasses of framework classes | grep `class .* extends CI_` and `function __construct` | Constructor calls `parent::__construct()` with no arguments, which fails on forks that inject dependencies |
| Logging | Subclass of the log class copying `write_log()` | read the subclass | Silent misbehaviour after the core change |
| Session | Custom session driver | grep `SessionHandlerInterface`, then `CI_Session_driver` under application | Missing interface methods or return types |
| Packages | `php` constraint, abandoned packages, lock file | `composer show -o` (needs vendor or lock), read composer.json | `"php": ">=5.6"`, no lock |
| Copied libraries | Duplicate copies of one library | `find . -name "Mongo_db*.php" -not -path "*/vendor/*"` | Several copies, only one patched |
| Error config | Every place that sets error reporting | sweep R group `error_visibility` plus `.htaccess` and image ini | Deprecations hidden in one or more places |
| Env switch | `CI_ENV` writers and readers | `grep -rn "CI_ENV" application index.php .htaccess` | A controller rewrites `.htaccess` |
| Web server | `php_value` or `php_flag` in `.htaccess` | grep `php_value` and `php_flag` in .htaccess files (root and public) | Valid only under mod_php |
| Secrets | Credentials in tracked files | Section 4 of `security-sweep.md` (names only) | Tracked `.env`, config files with keys |
| Dead features | Modules with no callers | Phase 5 checklist | Chat, Google, maps, test harnesses |
| Auth gate | Endpoints with no login check | `security-sweep.md` discovery commands | Harnesses and internal APIs open to anyone |
| CI | Existing lint or test stage | grep `php -l`, `lint` and `phpunit` in .gitlab-ci.yml and .github/workflows | No lint at all, or lint that reads only the exit code |
| Tests | Test suite present and runnable | `ls tests phpunit.xml*` (ignore errors if absent) | Often none; say so |
| Notes | Existing upgrade notes file | list docs/ and look for upgrade-related names | Notes may describe removed code |

## 5. Filtering rules for grep hits

The sweep script already drops comment-only lines and lines that match its per-pattern exclude. For anything you grep by hand, apply these filters and say which ones you used:

- Comment lines (`//`, `*`, `#`, `/*`, CI docblocks starting with `|`).
- JavaScript inside HTML or view files. `${x}` and backtick template literals are JS, not PHP.
- `mcrypt_*`, `create_function` and similar inside vendored libraries behind `function_exists` or `version_compare`. They do not run on PHP 8. Count them as "vendored, guarded" and do not fix them in the app.
- Method definitions named like removed functions (`function split(`, `function each(`).
- Hits inside a PHP string that happen to contain `<?xml` (not a short tag).

Report every number as "N after filters (M raw)". Never report a raw count as a defect count.

## 6. Common mistakes

- Counting raw grep hits as defects. One sweep looked like 293 F-group hits before comment and docblock filtering. The real count was 2.
- Stopping the audit at lint. Lint passing says nothing about NULL into internal functions.
- Reading only the files you suspect. For access control, enumerate every controller.
- Trusting the changelog of a fork. Read the code (the fork's `changelog.rst` was stale as of 2026-10).
- Forgetting copies. A fix applied to one of several copies of a library is not a fix.
- Calling something "unused" because no code calls it. Check routes, JS, cron, CI, and the database documents too.
