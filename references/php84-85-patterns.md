# PHP 8.x hazard patterns: grep, fix, and what lint misses

Use this file in Phase 2 (fatals) and Phase 4 (sweeps). Each entry has the grep that finds it (the same regex as `scripts/sweep-patterns.sh`, where a pattern exists there), the symptom, and a before and after.

## Contents

1. Which hazards lint catches
2. Fatal on PHP 8.0+ (group F)
3. Deprecated or behaviour change, 8.1 to 8.5 (group D)
4. Review patterns (group R)
5. Database driver and extension patterns
6. Verification

## 1. Which hazards lint catches

`php -l` (the compile check) reports compile-time problems. Checked by hand with `php -l` on `php:8.4-cli` and `php:8.5-cli` (test files written for this skill, outside any project).

| Hazard | `php -l` reports | Gate that catches it |
|---|---|---|
| Parse errors (`$s{0}`, `(real)`), `<?xml` as the first line with short tags on | Yes, as errors (both 8.4 and 8.5) | Lint |
| `(double)` cast | Yes, as `Deprecated`, on 8.5 only. Silent on 8.4 | Lint on 8.5, grep on 8.4 |
| `$http_response_header` | Yes, as `Deprecated`, on 8.5 only. Silent on 8.4 | Lint on 8.5, grep on 8.4 |
| `${var}` in a PHP string | Yes, as `Deprecated` (8.2 and later), exit code still 0 | Lint, read the output |
| Required parameter after optional | Yes, as `Deprecated` (since 8.0), on 8.4 and 8.5 | Lint, read the output |
| Implicit nullable `Type $x = null` | Yes, as `Deprecated`, on 8.4 and 8.5 | Lint, read the output |
| `implode($array, $glue)` | No, valid syntax | Grep, smoke run |
| NULL into internal functions (`json_decode(null)`, `strtoupper(null)`) | No | Grep, smoke run |
| `count(null)` | No | Grep, smoke run |
| `curl_close()` (deprecated 8.5) | No | Grep |
| `E_STRICT` constant (runtime deprecation on 8.4 when referenced) | No | Grep |
| `<? ... ?>` in an HTML-only file | No, in either mode. A `<?` that follows PHP code in the same file is a parse error, and lint catches that | Grep views |
| `is_resource()` on IMAP or cURL objects | No | Grep, smoke run |
| Dynamic properties (8.2) | No | Staging deprecation log, static review |
| Removed functions (`mysql_*`, `ereg`, `split`, `each`, `create_function`) | No, runtime undefined function | Grep, smoke run |
| Missing extension (`imap_open` with no imap) | No | `php -m` in the built image, grep callers |

Lint passing is the first gate, not the last.

## 2. Fatal on PHP 8.0+ (group F)

### F1. `implode()` with arguments reversed (fatal 8.0)

- Grep: `implode\([[:space:]]*\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*,[[:space:]]*['"]`
- Symptom: `TypeError: implode(): Argument #1 ($separator) must be of type string, array given`. Lint passes.

```php
// before
$text = implode($parts, ', ');
// after
$text = implode(', ', $parts);
```

Note: `implode($glue, $array)` is already correct. Check the variable name is the array before you swap. The sweep flags the literal-second-argument form only, because the other form is ambiguous; read any `implode($x, $y)` you find by hand.

### F2. Removed functions

- Grep (group F): `(^|[^A-Za-z0-9_.>:$\\])(mysql_[a-z_]+|eregi?|ereg_replace|eregi_replace|split|spliti|each|create_function|money_format|get_magic_quotes_gpc|get_magic_quotes_runtime|mcrypt_[a-z_]+)[[:space:]]*\(`

| Removed | Replacement |
|---|---|
| `mysql_*` | mysqli or the CI database driver |
| `ereg`, `eregi`, `ereg_replace`, `split`, `spliti` | `preg_match`, `preg_split`, `preg_replace` |
| `each()` | `foreach` |
| `create_function()` | closure |
| `money_format()` | `number_format()` or `NumberFormatter` |
| `get_magic_quotes_gpc()`, `get_magic_quotes_runtime()` | delete the branch (magic quotes is gone since 5.4) |
| `mcrypt_*()` | `openssl_*` or the framework's Encryption library. Data encrypted with mcrypt needs a re-encryption plan. |

```php
// before
if (get_magic_quotes_gpc()) { $value = stripslashes($value); }
// after
// removed: magic quotes no longer exists
```

Vendored code behind `function_exists()` or `version_compare()` never runs on PHP 8. Leave it alone and record it as "vendored, guarded". Upgrading the vendored library is the real fix, and that belongs in Phase 3 (packages).

Sample files shipped inside the app (such as CKEditor sample pages under `assets/` or `public/`) are not app code. Delete them with `git rm` after the user confirms (Phase 5).

### F3. Parse errors removed in 8.0

- String offset with braces: `\$[A-Za-z_][A-Za-z0-9_]*\{[0-9$'"]`

```php
// before
$first = $str{0};
// after
$first = $str[0];
```

- Cast `(real)`: `\((real)\)`

```php
// before
$f = (real) $x;
// after
$f = (float) $x;
```

- `assert()` with a string: `\bassert[[:space:]]*\([[:space:]]*['"]`

```php
// before
assert('$n > 0');
// after
assert($n > 0);
```

### F4. `$HTTP_RAW_POST_DATA` removed in 7.0

- Grep: `\$HTTP_RAW_POST_DATA`

```php
// before
$raw = $HTTP_RAW_POST_DATA;
// after
$raw = file_get_contents('php://input');
```

Remove dead branches that test it (for example `if (!is_php('5.4'))` blocks in a copied bootstrap) when you rebase the bootstrap.

### F5. PHP 4-style constructors

- Lint does not flag them. A method named like the class is no longer a constructor when the class has `__construct()`, and it is a plain method when it does not. The failure is silent when a class has no `__construct()`.
- Find: `grep -rnE "function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(" application` and compare each name with its class. Only a class with no `__construct()` is broken.

```php
// before
class Foo { function Foo($x) { $this->x = $x; } }
// after
class Foo { function __construct($x) { $this->x = $x; } }
```

### F6. Legacy Mongo classes (fatal once the adapter is removed)

- Grep: `\bMongo(Client|Id|Date|Regex|Code|Collection|Cursor)\b`
- Note: `MongoDB\BSON\...` is correct and must not match. The sweep excludes the bare `MongoDB` name on purpose.
- Mapping: see section 5.

## 3. Deprecated or behaviour change, 8.1 to 8.5 (group D)

### D1. NULL into internal functions (8.1 deprecation, TypeError in some functions)

`$this->input->post()` returns NULL when the key is missing. Any internal function that takes a string gets NULL.

- Grep: `json_decode[[:space:]]*\([[:space:]]*\$this->input->(post|get|get_post|post_get|cookie)\(` (exclude lines with `??`)
- Grep (other string functions): `(strtoupper|strtolower|trim|urldecode|rawurldecode|base64_decode|htmlspecialchars|strlen)[[:space:]]*\([[:space:]]*\$this->input->(post|get)\(`

```php
// before
$data = json_decode($this->input->post('data'), true);
// after
$data = json_decode($this->input->post('data') ?? '', true);
```

Do not use `(string)` in place of `?? ''` when the input can be an array (`post()` can return an array), because `(string)` turns an array into the literal `Array` with a notice. Use `?? ''`. The reference run applied this to about 150 sites under `application/`.

Other string functions in the same family (`strtoupper` on `$this->session->userdata(...)` before login, for example): the same fix. The runtime-only ones are not visible by grep. Check them in the smoke run, with a request that omits the parameter.

### D2. `count()` and `sizeof()` on NULL (TypeError 8.0)

- Grep: `(count|sizeof)[[:space:]]*\(` (review, do not mass-edit)

```php
// before
$n = count($rows);
// after, only where $rows can be NULL
$n = count($rows ?? []);
// or
$n = is_countable($rows) ? count($rows) : 0;
```

The reference run had about 150 call sites; most cannot be NULL. Guard the values that can be NULL. Do not edit all of them.

### D3. `"${var}"` interpolation in PHP strings (8.2 deprecation)

- Grep: `\$\{[A-Za-z_][A-Za-z0-9_]*\}`. Exclude backticks (JavaScript template literals).
- Only PHP strings count. Hits inside HTML or JavaScript in a view file (outside `<?php ... ?>`) are not PHP. Read each line.
- The sweep lists this pattern under R (review), because view files mix in JavaScript. The lint gate still fails on a real PHP hit.

```php
// before
$msg = "Hello ${name}";
// after
$msg = "Hello {$name}";
```

### D4. `utf8_encode()` and `utf8_decode()` (8.2 deprecation)

- Grep: `\butf8_(en|de)code[[:space:]]*\(`

```php
// before
$s = utf8_encode($raw);
// after
$s = mb_convert_encoding($raw, 'UTF-8', 'ISO-8859-1');
```

### D5. `strftime()`, `gmstrftime()`, `date_sunrise()`, `date_sunset()` (8.1 deprecation)

- Grep: `(^|[^A-Za-z0-9_.>:$])(strftime|gmstrftime|date_sunrise|date_sunset)[[:space:]]*\(`

```php
// before
echo strftime('%Y-%m-%d', $ts);
// after
echo date('Y-m-d', $ts);
// before
$info = date_sunrise($ts);
// after
$info = date_sun_info($ts, $lat, $lon);
```

Use `IntlDateFormatter` where locale formatting matters.

### D6. `FILTER_SANITIZE_STRING` (8.1 deprecation)

- Grep: `FILTER_SANITIZE_STRING`

```php
// before
$name = filter_var($input, FILTER_SANITIZE_STRING);
// after: validate for what you need, and escape at output
$name = trim((string) $input);
echo htmlspecialchars($name, ENT_QUOTES, 'UTF-8');
```

Removing the filter is a behaviour change: input is no longer stripped. Escape at output (Phase 6 and `security-sweep.md`).

### D7. Short open tags in views

- Grep (sweep pattern `short_open_tag`): `<\?` excluding `<\?php`, `<\?=`, and `<?` inside a PHP string.
- Lint cannot see them in either mode of `short_open_tag`. With short tags off, `<? echo 1 ?>` prints as raw text. With them on, `<?xml` on the first line is a parse error.

```php
// before (view)
<? echo $title ?>
// after
<?php echo $title ?>
```

`<?xml version="1.0"?>` inside a template: print it through PHP, `<?php echo '<?xml version="1.0"?>'; ?>`, so it is not a short tag.

One project had 28 such tags in three popup views. The fork has dropped `rewrite_short_tags`, so configuration cannot save you.

### D8. Implicit nullable parameters (deprecated 8.4)

- Grep: `([(,][[:space:]]*)[A-Za-z_][A-Za-z0-9_\\]*[[:space:]]+&?\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*null\b`

```php
// before
function save(Model $m = null) {}
// after
function save(?Model $m = null) {}
```

### D9. Required parameter after optional (deprecated since 8.0)

- Grep (heuristic, single-line signatures): see the `required_after_optional` pattern in the script.

```php
// before
function where_gt($field = '', $value) {}
// after: drop the default. PHP already ignored it, so behaviour is unchanged.
function where_gt($field, $value) {}
```

Before you do this, grep the callers. Every caller must pass the argument explicitly, which the default never guaranteed.

### D10. `E_STRICT` (deprecated 8.4 when referenced)

- Grep: `\bE_STRICT\b`
- Remove it from `error_reporting()` masks (`~E_STRICT` is harmless to drop). The reference run found it in `index.php` and the env bootstrap. The framework's `Exceptions.php` has its own copy (CI 3.1 core) and needs a literal `2048` in place of the constant when you patch in place.

```php
// before
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
// after: remove the mask entirely, see infra-and-docker.md
error_reporting(E_ALL);
```

### D11. `curl_close()` (deprecated 8.5)

- Grep: `\bcurl_close[[:space:]]*\(`
- Delete the call. The handle is freed when it goes out of scope (and `curl_close()` had no effect since 8.0). Check that nothing uses the handle afterwards.

```php
// before
$ch = curl_init($url);
curl_exec($ch);
curl_close($ch);
// after
$ch = curl_init($url);
curl_exec($ch);
```

### D12. Deprecated casts (8.5)

- Grep: `\((double|boolean|integer|binary)\)`

| Before | After |
|---|---|
| `(double)` | `(float)` |
| `(boolean)` | `(bool)` |
| `(integer)` | `(int)` |
| `(binary)` | `(string)` |

Lint reports these only on 8.5, not 8.4. Run the gate on 8.5 as well as the target, and keep the grep. Comments and docblocks mention these casts too, and the sweep drops those lines.

### D13. `$http_response_header` (deprecated 8.5)

- Grep: `\$http_response_header`

```php
// before
$body = file_get_contents($url);
$headers = $http_response_header;
// after, PHP 8.4+
$body = file_get_contents($url);
$headers = http_get_last_response_headers();
// after, works on older PHP too (the form that also works on older PHP)
$body = file_get_contents($url);
$headers = get_defined_vars()['http_response_header'] ?? null;
```

The reference run chose the second form because not every image was on 8.4 yet. Pick one and state it in the notes.

### D14. `is_resource()` on IMAP and cURL objects (8.1)

- Grep: `\bis_resource[[:space:]]*\(`
- `imap_open()` returns an `IMAP\Connection` object and `curl_init()` returns a `CurlHandle` object since 8.1. `is_resource()` returns false for them.

```php
// before
if (is_resource($this->stream)) { ... }
// after
if ($this->stream instanceof \IMAP\Connection || is_resource($this->stream)) { ... }
// cURL
if ($ch instanceof CurlHandle) { ... }
```

### D15. `fputcsv()` without `$escape` (deprecated 8.4)

- Grep: `\bfputcsv[[:space:]]*\(`

```php
// before
fputcsv($out, $row);
// after
fputcsv($out, $row, ',', '"', '\\');
```

### D16. Dynamic properties (deprecated 8.2)

- Lint and grep cannot see these. Two ways to find them:
  1. Staging: run with `error_reporting(E_ALL)` and `display_errors` off, log to a file, and exercise the app. The log shows `Creation of dynamic property`.
  2. Static: classes that assign `$this->name = ...` where `name` is not declared in the class.
- Fix: declare the property (`private $x;`, or the type you need).
- `#[\AllowDynamicProperties]` is for framework base classes you do not own. The fork already sets it on `CI_Controller`, `CI_Model`, `CI_Loader`, `CI_DB_driver` and `CI_Driver_Library`, but not on `CI_Router`, `CI_Config`, `CI_Session`, `CI_Driver` or `CI_Profiler`. Do not add it to app classes just to silence the message.

```php
// before (a module hook sets a property on CI_Router)
$this->_RTR->module = $module;
// after: store it where you own the class, or extend the router
$this->module = $module;
```

### D17. Implicit float-to-int conversion (deprecated 8.1)

- Lint and grep cannot see the argument type. Look for functions that take integers (`mt_rand`, `imagecreate`, `str_repeat`, `substr` with computed offsets) when the argument can be a float. Cast explicitly: `(int) $x`.

### D18. `setcookie()` and `delete_cookie()` with an empty name or NULL value

- `delete_cookie('')` throws `ValueError` on 8.x. A CI helper that receives an empty name (for example with a session-persistence flag set to FALSE) turns logout into HTTP 500 (seen in one project).
- `setcookie(..., NULL, ...)` is deprecated. Pass `''`.
- Grep: `delete_cookie[[:space:]]*\(` and `setcookie[[:space:]]*\(`.

```php
// before (inside the helper)
function delete_cookie($name) { setcookie($name, '', time() - 3600); }
// after
function delete_cookie($name) {
    if ($name === '' || $name === null) { return; }
    setcookie($name, '', time() - 3600);
}
```

### D19. `scandir()` returns false

- Grep: `\bscandir[[:space:]]*\(`
- When the directory is missing (common on a mounted NAS), `scandir()` returns false, and `array_diff()` on it throws.

```php
// before
$items = array_diff(scandir($path), ['.', '..']);
// after
$items = array_diff(scandir($path) ?: [], ['.', '..']);
```

### D20. `strtoupper()` and similar on NULL session values

- Covered by D1 in spirit: a session value read before login is NULL. Use `(string) $this->session->userdata('x')` at that call site, after checking that an array is impossible there.

### D21. `unserialize()` on untrusted input

- Grep: `\bunserialize[[:space:]]*\(`
- Not a PHP 8 error, but an unrestricted class instantiation risk. Where the input is not fully trusted, pass `['allowed_classes' => false]`. Verify the data really holds no objects before you do.

```php
// before
$data = unserialize($blob);
// after, where the blob holds only arrays and scalars
$data = unserialize($blob, ['allowed_classes' => false]);
```

### D22. Error-visibility masks

- Grep: `error_reporting[[:space:]]*\(|display_errors|E_DEPRECATED`
- This is an infrastructure fix, not a code fix. See `infra-and-docker.md`, section 3.

## 4. Review patterns (group R)

These have many hits and need a human. Record the decision per group, not per hit.

| Pattern | Why it matters | Decision to record |
|---|---|---|
| `count` and `sizeof` | TypeError on NULL | Which call sites can be NULL |
| `is_resource` | IMAP and cURL objects | Each argument's type |
| `scandir` | false on missing directory | Each directory's presence guarantee |
| `unserialize` | class instantiation | Whether input is trusted |
| `fputcsv` | 8.4 deprecation without `$escape` | Which call sites omit it |
| `is_callable` with `[$this, ...]` | can return false for non-static methods on 8.x | Replace with `method_exists()` or `ReflectionMethod` |
| `error_reporting`, `display_errors` | deprecations hidden | All masks agree (infra) |
| `imap_*`, `ftp_*`, `new Soap*` | extensions must be in the image | Install only with a caller; see infra |
| `load->library('encrypt')`, `sha1`, `->encrypt->` | the fork removed Encrypt and Sha1 | Migrate to Encryption or `hash()` |

## 5. Database driver and extension patterns

### Legacy Mongo to `MongoDB\Driver\Manager` (ext-mongodb 1.x and 2.x)

Symptom: `Class "MongoClient" not found`, `Class "MongoId" not found`, or `Expected options to be array, MongoDB\Driver\ReadPreference given`.

| Legacy | Replacement |
|---|---|
| `new MongoClient(...)` | `new MongoDB\Driver\Manager($uri, $options)` |
| `new MongoId($s)` | `new MongoDB\BSON\ObjectId($s)` |
| `(string) $doc['_id']` instead of `$doc['_id']->{'$id'}` | `(string) $doc['_id']` |
| `new MongoDate($sec)` | `new MongoDB\BSON\UTCDateTime($ms)` with milliseconds as an int, `(int) round($stamp * 1000)` |
| `new MongoRegex('/x/i')` | `new MongoDB\BSON\Regex('x', 'i')` |
| `MongoCollection::remove(..)` | `executeBulkWrite` with a delete operation (`limit` 0 deletes many) |
| `RP_PRIMARY` | `'primary'` (`new ReadPreference('RP_PRIMARY')` throws Invalid mode) |
| `$manager->executeQuery($ns, $q, $readPreferenceObject)` | `$manager->executeQuery($ns, $q, ['readPreference' => new ReadPreference('primary')])` |
| `executeBulkWrite(..., $writeConcern)` | options array: `['writeConcern' => new WriteConcern(1)]` |
| `new UTCDateTime(float)` | `new UTCDateTime((int) round($x))` |

Caveats:

- Pick the ext-mongodb version that matches the MongoDB server in use. The reference run pinned 1.19.4 for servers 3.6 and 4.x, with the same version in dev and prod.
- The PHP library (`mongodb/mongodb`) must match the extension's major version. Mismatch gives a compile error in `vendor/mongodb/...` on every request (seen in one project: ext 2.5.5 with library 1.21.5).
- Values returned from documents change type (`ObjectId`, `UTCDateTime`). Check any `json_encode()` of raw results: the JSON shape changes (`{"$oid": ...}`).

### Extensions

- `imap_*` needs `imap`. Installed via `install-php-extensions imap` (mlocati) in the reference Dockerfile.
- `ftp_*` needs `ftp`. The official `php:*-cli` image does not have it. Build it with `docker-php-ext-install ftp` and verify with `php -r 'echo function_exists("ftp_connect") ? "yes" : "no";'`.
- `SoapClient` needs `soap`.
- `oci_*` needs the Oracle Instant Client. Plan this as a separate task.

## 6. Verification

After a fix:

1. Rerun the sweep and confirm the count dropped by exactly what you changed. A drop with no change means a regex or filter problem, not success.
2. Run the lint gate at the target and check the output.
3. For runtime-only patterns (D1, D2, D20, D16, F2 in guarded code), run the smoke request that exercises the path, with the parameter omitted, and read the response body and the log.
4. Record the before and after counts in the notes.
