# Swapping the CodeIgniter core (Phase 2b)

Use this file when Phase 0 chose to move from a bundled CodeIgniter 3.1.x (or 2.2.6) to the `hoangkim28/codeigniter` fork, or when you patch the bundled core in place. The reference run did the swap; a second project patched in place. Both paths are described.

## Contents

1. Facts about the fork (verified and from the docs)
2. Choosing: swap or patch in place
3. Pre-checks
4. Swap steps, in commit order
5. Subclass rules and the constructor table
6. Log and session subclasses
7. Behaviour changes to test (table)
8. Entry points and bootstrap
9. Encrypt to Encryption
10. Smoke list
11. Rollback
12. From CodeIgniter 2.2.6

## 1. Facts about the fork

Verified in a local clone of the fork (`system/core/CodeIgniter.php`, `Input.php`, `Log.php`, `Router.php`) in October 2026. Re-check them against the commit or tag you pin:

- `CI_VERSION` is `'3.4.5'` (a constant, not a release). The fork is built on an unreleased upstream 3.2.0-dev line. Do not claim it is an official BCIT release.
- Packagist name `hoangkim28/codeigniter`, version `v0.2.1` (per the bundled team docs, `references/upgrade-docs/README.md` section 1, 2026-10-23; check Packagist for the current tag). The git history of the fork's `develop` branch had one commit (as of 2026-10), so you cannot trace changes. **Pin an exact commit or tag, never `develop`.** Ask the fork's owner what "3.4.5" means before production.
- The fork's `changelog.rst` is stale. It says some features were removed that the code still has (Cart, Email helper, `form_prep`, and others). **Trust the code, not the changelog.** Grep the function before you assume it is gone.
- Constructors changed (verified):

| Class | Constructor on the fork |
|---|---|
| `CI_Hooks` | `__construct(CI_Config $config)` |
| `CI_URI` | `__construct(CI_Config $config)` |
| `CI_Utf8` | `__construct($charset)` |
| `CI_Security` | `__construct($charset)` |
| `CI_Input` | `__construct(CI_Security &$security)` |

- `#[AllowDynamicProperties]` is on `CI_Controller`, `CI_Model`, `CI_Loader`, `CI_DB_driver` and `CI_Driver_Library` only. Not on `CI_Router`, `CI_Config`, `CI_Session`, `CI_Driver` or `CI_Profiler`. Code that sets undeclared properties on the second group raises deprecations.
- Routes: `(:any)` is now `[^/]+` (verified in `Router.php`). It used to be `.+`, which matched slashes.
- The log class keeps `_log_filename` and `_log_filename_dated` (verified). The old `_file_ext` is gone. Subclasses that copied `write_log()` from 3.1 break silently.
- The session layer has `CI_Session_driver_interface` (verified), and `PHP8SessionWrapper` type-hints it.

## 2. Choosing: swap or patch in place

| Situation | Choice | Why |
|---|---|---|
| `system/` is unpatched upstream 3.1.x, and the team accepts the fork's behaviour changes (section 7) | Swap (reference run) | Less code to own; the fork has the PHP 8 fixes |
| `system/` is patched, bootstrap copied into the app, custom cache drivers in core (second project) | Patch in place first (the second project's path), move the patches to app-level subclasses, then decide on the swap | A swap in one step would rewrite bootstrap, input, log and session together |
| Team cannot accept fork behaviour (no input filtering, `(:any)` change) | Patch in place, record the fork as a later option | Scope control |

The reference run did not patch the core in place, because `system/` was unpatched. The second project's patches (Profiler, Exceptions, Session, cookie helper, Input, Output) are PHP 8 fixes to CI 3.1.9. Those are the patches to re-apply, in the fork's terms, if you stay on 3.1.

## 3. Pre-checks

Run before you touch `system/`. The goal: find app files hiding in the framework tree.

```bash
APP=.
UP=/path/to/clean/upstream/3.1.x        # a clean checkout of the same version, read-only use
diff -rq "$APP/system" "$UP/system" | head -80
diff -rq "$APP/system" "$UP/system" | grep '^Only in'      # files that exist only in the app's system/
git ls-files system | wc -l
```

Expect "Only in" lines for things like a JSON config file under `system/config/`, a dead controller copy, or a `.htaccess` you added. Each one is app-owned. Move it before the swap.

The reference run: a JSON config file moved to `application/config/` (read through `APPPATH` by the app's config loaders), and a dead controller copy was deleted. The move was committed after the swap commit, not before. The reference playbook says move first. Do the move first.

Also check:

```bash
ls application/core/                                     # bootstrap copy?
grep -rn "APPPATH.*CodeIgniter.php\|BASEPATH.*CodeIgniter.php" index.php public/index.php 2>/dev/null
grep -rnE "class[[:space:]]+(MY_|APP_|[A-Za-z]+_)?(Hooks|URI|Utf8|Security|Input|Log|Loader|Router|Output|Session)\b" application
grep -rn "load->library(\s*['\"]encrypt['\"]\|load->library(\s*['\"]sha1['\"]" application
```

## 4. Swap steps, in commit order

Each step is its own commit, and each one leaves the project lintable.

1. **Move app-owned files out of `system/`.** Commit. Run the lint gate.
2. **Pin the fork.** `composer require hoangkim28/codeigniter:<exact-version>` or vendor the commit. Commit `composer.json` and the lock.
3. **Replace `system/`.** Remove the old tree and copy the fork's `system/` in. Do not copy over the top, because old files like `Encrypt.php`, the `sqlite/` driver directory and `SessionHandlerInterface.php` must disappear (the bundled `references/upgrade-docs/UPGRADE_FROM_3.1.13.md` lists these). Commit.
4. **Fix the entry points.** `index.php` `$system_path`, the `error_reporting` block (section 8), `public/index.php`, and test bootstraps (`tests/Bootstrap.php` and anything under `tests/`). Commit.
5. **Fix the subclasses** (section 5), the log subclass and the session driver (section 6). Commit each.
6. **Fix the bootstrap copy** if one exists (section 8).
7. **Fix the behaviour changes** (section 7), one theme per commit.
8. **Run the smoke list** (section 10).

Note the order matters: the entry points cannot load until `system/` is replaced; the subclasses cannot be checked until the new constructors exist.

## 5. Subclass rules and the constructor table

See also: the same constructor table is in `references/upgrade-docs/UPGRADE_FROM_3.1.13.md` (around line 38) and in the bundled playbook, section 8.3.

Any subclass that overrides a constructor must pass the new dependencies. The call `parent::__construct()` with no arguments fails with `ArgumentCountError`.

```php
// Input subclass: before
class APP_Input extends CI_Input {
    public function __construct() {
        parent::__construct();
    }
}
// after
class APP_Input extends CI_Input {
    public function __construct(CI_Security &$security) {
        parent::__construct($security);
    }
}
```

| Subclass prefix | Class | Constructor to write |
|---|---|---|
| `MY_` or your prefix | `Hooks` | `__construct(CI_Config $config)` |
| | `URI` | `__construct(CI_Config $config)` |
| | `Utf8` | `__construct($charset)` |
| | `Security` | `__construct($charset)` |
| | `Input` | `__construct(CI_Security &$security)` |

Grep for overrides first:

```bash
grep -rnE "class[[:space:]]+[A-Za-z_]+[[:space:]]+extends[[:space:]]+CI_(Hooks|URI|Utf8|Security|Input)\b" application
```

Copies matter. A class in `application/libraries/` with the same name as a core class is not a subclass unless it extends the core class. Check the `extends` clause.

## 6. Log and session subclasses

### Log

A subclass that copies `write_log()` from 3.1 writes the wrong file name (missing the extension) and loses the access-blocking header the core writes. Fix: keep only the app-specific side effects, then delegate.

```php
// before: copy of the 3.1 write_log(), uses $this->_file_ext (gone)
public function write_log($level, $msg, $php_error = FALSE) { /* 60 lines */ }

// after: app side effects, then the core
public function write_log($level, $msg, $php_error = FALSE)
{
    if ($level === 'ERROR') {
        $this->notify_error($msg);          // app-only behaviour, keep
    }
    return parent::write_log($level, $msg);
}
```

Check the signature the fork uses for `write_log()` before you copy it. The reference run's log subclass kept its `notify_error()` and `write_log_db()` and delegated the file writing. Also guard the error path: a log call during controller construction can run before `$CI->load` exists. Check `class_exists('CI_Controller', FALSE)` and `is_object($CI) && isset($CI->load)` before you use the controller.

### Session driver

The fork's session wrapper type-hints `CI_Session_driver_interface`. A driver that only implements `SessionHandlerInterface` does not match.

See also: the bundled playbook, section 8.4 (`references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md`), has the same driver example and the same requirements.

Requirements for a custom driver (for example a MongoDB driver):

- Extend `CI_Session_driver` and implement both `SessionHandlerInterface` and `CI_Session_driver_interface`.
- Implement `open`, `read`, `write`, `close`, `destroy`, `gc`, plus `updateTimestamp($id, $data)` and `validateId($id)`.
- Return `bool` where the wrapper declares `: bool`, for `open`, `write`, `close`, `destroy`. Use `#[\ReturnTypeWillChange]` for `read` (it may return NULL) and `gc` (the interface allows int or false).
- Declare `protected $_row_exists = NULL;` if the driver's `write()` uses it (declaring it avoids a dynamic property).
- `validateId()` must use the same filter as `read()`, because strict mode is on in the 3.1 configuration.
- `updateTimestamp()`: if `read()` finds no row, or the id changed, call `write()`; otherwise only set the timestamp.

```php
class CI_Session_mongo_driver extends CI_Session_driver
    implements SessionHandlerInterface, CI_Session_driver_interface
{
    protected $_row_exists = NULL;

    #[\ReturnTypeWillChange]
    public function updateTimestamp($id, $data) { /* as above */ }

    #[\ReturnTypeWillChange]
    public function validateId($id) { /* as above */ }
}
```

Config: `sess_driver` set to your driver's short name. The reference run set it to `mongo`.

Test it: login, logout, `session_regenerate_id`, a stale session id (the id must be replaced with a new one), and a second request reusing the session. These are the most fragile paths.

## 7. Behaviour changes to test

Lint will not catch these. Each row: change, why it bites, how to find affected code, what to test.

Grep notes: each "Find" column is one search. Where a row names more than one word, run one grep per word, so that no command needs a pipe inside this table.

| # | Change | How it bites | Find | Test |
|---|---|---|---|---|
| 1 | Global input filtering removed (`_sanitize_globals` gone) | Output that echoed `$_GET`, cookies or `PHP_SELF` unescaped is now XSS | grep `_GET`, then `_POST`, `_COOKIE`, `PHP_SELF` under application, and check every echo | Send a script tag in a GET parameter and check the page |
| 2 | `(:any)` is `[^/]+` | Routes that matched multi-segment paths now 404 | grep `(:any)` in application/config/routes.php | Request a multi-segment path |
| 3 | `where_in` family requires arrays | Empty arrays throw `InvalidArgumentException` | grep `where_in(` and `where_not_in(` (the `or_` forms match too) | Empty-list case in each caller |
| 4 | Connection failure throws `RuntimeException` | Manual `load->database()` without try/catch fails the request | grep `load->database` under application | Stop the DB and request a page |
| 5 | `stricton` FALSE disables strict SQL mode | Config key present with FALSE turns strict off | grep `stricton` under application/config | Remove the key to use the server default |
| 6 | Query builder always loaded, `$query_builder` ignored | Old config flags do nothing | grep `query_builder` under application/config | Load a page using the DB |
| 7 | Output cache key format changed | Old cached pages can be served wrongly | list `application/cache` | Clear `application/cache` at cut-over |
| 8 | Email `validate` defaults to TRUE | Addresses that passed before now fail | grep `load->library('email')` under application | Send to a bad address |
| 9 | View variables no longer leak to the next view | Views that relied on leaked variables break | grep `load->view(` and count lines; grep `load->vars(` | Each view that reads a variable it did not receive |
| 10 | Log levels changed (`debug` to `info` in core) | Debug lines vanish at the same threshold | grep `log_threshold` under application/config | Set threshold to what you need |
| 11 | Session: missing key returns NULL; `unset_userdata` takes a list of keys; metadata gone | `session_id`, `ip_address`, `user_agent` are no longer user data | grep `userdata('session_id')`, then `ip_address`, `user_agent`, `last_activity` | Login and session reads |
| 12 | `redirect()` default 303 or 307 | Method-dependent; some clients behave differently | grep `redirect(` under application | Form POST then redirect |
| 13 | CSRF cookie `SameSite=Strict`, 403 on failure | Cross-site callbacks fail | grep `csrf` under application/config | Webhook round-trip on staging |
| 14 | Encrypt library removed, Encryption differs | Data encrypted with the old library cannot be read | grep `encrypt->`, then `library('encrypt')` | Read an old encrypted value; plan re-encryption |
| 15 | `form_validation` changes (empty rules throw, lang keys need prefix) | Validation pages error | grep `set_rules(` under application | Submit each form, valid and invalid |
| 16 | Migration type defaults to `timestamp` | Old sequential migration names stop running | grep `migration` under application/config | Run migrations on a copy |
| 17 | `Router::$directory` defaults to `''` | Code testing NULL behaves differently | grep `router->directory` under application | Directory routes |
| 18 | `DIR_WRITE_MODE` default 0755 (was 0777) | Writes fail for the web user | grep `DIR_WRITE_MODE` under application | Upload and log writes |
| 19 | `url_title()` keeps Unicode | Slugs keep accents | grep `url_title(` under application | Slug from accented text (for example Vietnamese) |
| 20 | `force_download()` MIME default `application/octet-stream` | Files download with a generic type | grep `force_download(` under application | Download each type |
| 21 | `create_captcha()` takes an array only, PNG only | Old positional calls break | grep `create_captcha(` under application | Captcha page |
| 22 | `auto_typography()` lost its third parameter | Old three-argument calls change meaning | grep `auto_typography(` under application | Each call |
| 23 | `set_cookie()` default expire 0 (session cookie) | Persisted cookies disappear | grep `set_cookie(` under application | Remember-me flow |

Treat this table as the test plan. Mark each row tested, not applicable, or open in the report.

## 8. Entry points and bootstrap

### `index.php`

- `$system_path` points at the fork's `system/` (Composer vendor path or the copied tree, as decided).
- Replace the `error_reporting()` block with one policy (`infra-and-docker.md`, section 3). The fork's `index.php` sets a sensible default for PHP 8.4. Merging your environment switch into it is acceptable. Do not keep `~E_DEPRECATED` in production.
- Remove `E_STRICT` from any mask (it is deprecated when referenced on 8.4).

### Bootstrap copy

If the app has `application/core/CodeIgniter.php` and the entry point loads it instead of `BASEPATH/core/CodeIgniter.php`:

1. Diff the copy against the upstream bootstrap of the same version, so you keep only the app's changes (the second project's were a `pre_check_controller` hook and a module-remap branch).
2. Rebase the app changes onto the fork's `CodeIgniter.php`.
3. Remove dead blocks such as `!is_php('5.4')` branches that reference `$HTTP_RAW_POST_DATA`.
4. Check every `load_class('Hooks' | 'Utf8' | 'URI' | 'Security' | 'Input', 'core')` call. Old calls pass no arguments; the fork's constructors need the dependencies (section 5). Left alone, they fatal.
5. Prefer no bootstrap copy at all. The reference run had none, so it needed no rebase.

## 9. Encrypt to Encryption

- The fork removed the `Encrypt` library. `$this->load->library('encrypt')` fails.
- The output is not compatible: the old library used mcrypt Rijndael-256; the new one uses OpenSSL AES. Data written by the old library cannot be read by the new one.
- Plan: inventory the encrypted fields, decide whether they must be re-encrypted (read with the old code first, write with the new), and whether the encryption key config is the same. Ask the user before any re-encryption run. Test on a copy.
- `Encryption` requires `encryption_key`. An empty key makes it refuse to work.

## 10. Smoke list

Run on staging or a local container with the services the app needs. Record what you ran and what you saw.

1. Home page and the sign-in page (no warnings in the body, no 500).
2. Login, logout, remember-me if present, session regeneration through an AJAX call.
3. One request with a stale or foreign session id (it must get a new id).
4. One authenticated JSON API: response is valid JSON with nothing before the first brace.
5. Each controller family, at least one endpoint, with a session (the reference run checked 27 modules this way in one project).
6. One export to Excel and to CSV, with real data if you can.
7. One upload and one download through a route with `(:any)`.
8. One cron or CLI job (`php index.php <controller> <method>`), and one queue worker start.
9. One mail send, if mail is in scope (SMTP) and one IMAP read, if used.
10. One third-party callback (sign-off test only on staging).
11. Logs: check for `Deprecated`, `Warning`, `Fatal` in `docker logs` after the run.

## 11. Rollback

- Keep the old `system/` and the old image tag. Tag the commit before the swap.
- The fork is installed by Composer, so a rebuild of the old commit needs `composer install` to work. If the build machine cannot reach Packagist, ship `vendor/` in the image, or use a mirror. The reference run's Dockerfile runs `composer update` at build time, so rebuilding an old commit can pull different package versions. Roll back by redeploying the old image, not by rebuilding.
- Cache: a cut-over that changes cache key formats needs the cache cleared on rollback too.

## 12. From CodeIgniter 2.2.6

The bundled team docs (`references/upgrade-docs/README.md` section 4) recommend a two-step path for large apps: 2.2.6 to 3.1.13 first (the official 21-step guide, `user_guide/installation/upgrade_300.html`), then 3.1.13 to the fork. Direct 2.2.6 to the fork is shorter but carries both sets of changes at once. The 2.x-specific items are in `references/upgrade-docs/UPGRADE_FROM_2.2.6.md`, and include: rename files to Ucfirst (Linux 404s otherwise), `mysql` to `mysqli`, rewrite the session layer, `NULL` instead of `FALSE` from input and config, and `stricton`. Read it, or the official CodeIgniter upgrade guides, before planning a 2.x path.
