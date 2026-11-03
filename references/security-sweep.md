# Auth-gap audit and secret handling (Phase 6)

An upgrade is the moment the access gaps in old controllers get seen, because you now read every controller. The reference run found an open test harness that sent SMS and read card transactions, a widget CRUD open to anyone, and a core API returning customer data. None of those was a PHP 8 problem. Treat this phase as part of the upgrade, not an extra.

## Contents

1. What "gated" means here
2. Discovery commands (tested on the reference project)
3. Classification
4. Secrets: names only
5. The fix pattern
6. Things that break when you gate an endpoint
7. Verification
8. CSRF and webhooks
9. Residual-risk wording

## 1. What "gated" means here

- A **login gate** means the request has a logged-in session. In the reference run it was `$this->authentication->check_login()`, which checks a session value and redirects anonymous requests to `page/signin` with a 302. Find your app's equivalent in its base controller (section 2) and read `check_login` in this file as that call.
- A login gate is not a **permission check**. Per-module permissions (`check_permissions()` in the app's base controller) are a separate control. The new gates in this phase add login only. Say so in the report.
- Every public method of a controller is routable by URL in CodeIgniter. A "helper" that is `public` is an endpoint.

## 2. Discovery commands

Run from the project root. These are read-only.

```bash
# 1. Base classes that controllers extend (find any gate hidden in a base class)
grep -rhoE "extends[[:space:]]+[A-Za-z_]+" application/controllers | sed -E 's/extends[[:space:]]+//' | sort | uniq -c

# Set from command 1 and the base class's constructor (reference run: APP_Controller and check_login)
BASE=APP_Controller   # the app's base controller that requires login
GATE=check_login      # the call it makes to require login

# 2. Where the base class gates
grep -rniE "class[[:space:]]+$BASE" application        # -i: the keyword may be spelled "Class"
grep -n "function __construct\|$GATE" "application/core/$BASE.php"

# 3. Direct subclasses of CI_Controller with no gate call anywhere in the file
grep -rlE "extends[[:space:]]+CI_Controller" application/controllers | xargs grep -L "$GATE"

# 4. Subclasses of the gated base whose constructor does not call the parent (would lose the gate)
for f in $(grep -rlE "extends[[:space:]]+$BASE" application/controllers | xargs grep -l "function __construct"); do
  grep -q "parent::__construct" "$f" || echo "NO PARENT CALL: $f"
done

# 5. Public methods (every one is URL-reachable unless it starts with _)
grep -rnE "^[[:space:]]*public[[:space:]]+function" application/controllers | wc -l
grep -rnE "^[[:space:]]*function[[:space:]]+" application/controllers | grep -v "__construct\|private\|protected" | head -50
```

Results from the reference run (for calibration only, not facts for your project):

- 45 files extend `CI_Controller` directly. 11 of them have no `check_login` string.
- 135 files extend `APP_Controller`. All of them inherit the gate, and the 134 that define a constructor all call `parent::__construct()`.
- Public methods across controllers: 130 (grep count, includes methods not routed).

Also find **self-calls over HTTP**. A hook or library that calls your own endpoint with `file_get_contents(base_url(...))` or `curl` carries no session, so a new gate breaks it:

```bash
grep -rnE "base_url\(|https?://" application/hooks application/libraries application/helpers | grep -v "^[^:]*:[0-9]*:[[:space:]]*(//|\*)" | head -30
```

In the reference run, an activity-log hook calls one of the app's own endpoints through `file_get_contents(base_url(...))` with no session. That endpoint is among the 11 ungated ones. Gating it blindly would silently stop activity logging.

## 3. Classification

Put every endpoint from the discovery list in one row of this table. Do not finish the phase with an unclassified row.

| Class | Examples (generalised) | Action |
|---|---|---|
| Login page and its assets | sign-in action, sign-in page, JS environment file served before login | Keep public. Make sure the response reveals nothing user-specific (one project stopped a contact list leaking to anonymous users) |
| Internal API or template used by logged-in pages | Widget and monitor controllers, internal template partials | Add the gate |
| Secret-authenticated webhook | telephony and card-service callbacks that check a shared secret in the request | Keep public. Check the secret comparison uses `hash_equals()` and reads from config, not a literal |
| Cron or CLI job reached over HTTP | "check timeout", "check email ticket", "check logout" controllers | Make CLI-only where possible (`if (!is_cli()) show_404();`) or require a secret. Ask the user which way |
| Self-call without session | the activity-log hook above | Change the caller to invoke the method directly (not over HTTP), or pass a token. Ask before changing the caller |
| Heartbeat or ping | a ping endpoint that checks the session | Gate it. Check how the front end handles the redirect |
| Test or harness controller | a controller that sends SMS or reads transactions with no check | Delete (Phase 5), after the user confirms |
| Unknown | anything you cannot classify | Ask the user. Record as open in the report |

## 4. Secrets: names only

Never print a secret value. Report the file path, line, and key name. The commands below print only names.

```bash
# Key names that look like credentials (the match is the quoted key name, never the value)
grep -rnoE "['\"][A-Za-z_]*(password|passwd|secret|api_?key|client_secret|token)[A-Za-z_]*['\"]" application --include=*.php | sort -u

# Files that are tracked and look like secret stores (paths only)
git ls-files | grep -E '(^|/)\.env|config/.*(mail|imap|database|mongo)' 

# Is a value in git history? Names and paths only; do not show diffs
git log --all --oneline -- <path> | head
```

Do not run `cat`, `git show` or `git diff` on a secret file, and do not paste output that includes a value. If you must confirm a value is non-empty, say you confirmed "set" or "empty" without showing it.

What to do with what you find:

1. List each file path and key name in the report under "ops action: rotate". Mention whether it is in history.
2. Do not rewrite history. Do not delete the file in a way that hides it from review; a `git rm` is fine as a separate, approved commit.
3. Hard-coded secrets in code (for example a constant in a controller): recommend moving to config or the environment, and rotating. Do the code move only if the user approves.
4. Hand the list to the person who can rotate keys. This skill does not rotate anything.

The pattern to copy from the reference run: integration secrets that had been removed from source but were still in git history, a secret hard-coded as a constant in controllers, and a mail password in a tracked config file all went to ops the same way, as a name-only list for rotation.

## 5. The fix pattern

Add the gate to the constructor, after `parent::__construct()`, using the same calls the base class uses:

```php
class Widget extends CI_Controller
{
    function __construct()
    {
        parent::__construct();
        $this->load->library('session');
        $this->load->library('authentication');
        $this->authentication->check_login();
        // ... the rest of the original constructor, unchanged
        header('Content-type: application/json');
        $this->load->library('crud');
    }
}
```

Rules:

- Gate at the constructor, so every method is covered. Do not gate one method and forget the next.
- Do not add permission logic in this phase. Login only, and write it down.
- Keep the original constructor code after the gate. Only the lines you add are new.
- Make helper methods `private` or `protected`. A `public function helper()` is a URL.
- CodeIgniter does not route methods starting with `_`, nor private or protected methods (`references/ci3-fork-swap.md`).

Making a helper private, example from the reference run: two public helpers in a service controller (a debt-reminder write and a card-transaction remark) could be triggered by URL. Only a webhook called them, so they became `private`.

## 6. Things that break when you gate an endpoint

- **Redirects for JSON clients.** `check_login()` redirects to the sign-in page with a 302. A JavaScript caller then receives HTML where it expected JSON. The reference run noted this in its notes. Options: accept it and document it; or return a JSON 401 from API controllers only (a new branch in the gate, tested with the front end). Ask the user.
- **Self-calls** (section 2). Change the caller or keep the endpoint public with a secret. Never gate it silently.
- **Cron over HTTP.** The scheduler may call the URL with no session. Gate it and the job stops. Move it to CLI first.
- **Sessions dropped by the framework change.** If the session driver or session cookie changes in the same release, every user is logged out once. Put that in the notes and the release message.
- **Pages that are fine logged out but now redirect in a loop.** The sign-in page must stay public. Check the redirect target.

## 7. Verification

Run this against staging or a local container. Never against production. Set the host through a variable; do not commit it.

```bash
BASE="${BASE:-http://localhost:8080}"   # staging or local container only
# endpoints.txt: one path per line, from the classification table
while IFS= read -r path; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$BASE/$path")
  loc=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 15 "$BASE/$path")
  printf '%-6s %-60s %s\n' "$code" "$path" "$loc"
done < endpoints.txt
```

Expected for every endpoint in the "gate" class: `302` to the sign-in page, or `401`, or `403`. Never `200`. Expected for public classes: whatever the classification says, and the response must not include user data.

Also check the no-session behaviour of the self-call and the cron endpoints separately, since they are the ones you decided on.

Record the table in the report: endpoint, class, code, and a note.

## 8. CSRF and webhooks

- The fork's CSRF cookie uses `SameSite=Strict`. A cross-site POST callback from a payment gateway or an external system loses the cookie and fails with 403. Add those URIs to `csrf_exclude_uris` only after you have read the callback's secret check.
- A webhook excluded from CSRF is still reachable by anyone. Its secret check is the control. Verify that check: constant-time comparison, secret from config, no default value.
- Do not exclude a whole directory from CSRF to make one callback work.

## 9. Residual-risk wording

Use this wording in the report, adjusted to the facts:

> Login gate added to N controllers (list in the appendix). The gate checks for a logged-in session only; per-module permissions are not checked by the new gates. Endpoints left public: <list, with reason>. Endpoints needing a decision: <list>. Secrets found in tracked files: <list of paths and key names>, referred to ops for rotation; history not rewritten. Verified by unauthenticated requests against <environment>: <counts by status code>. Not verified: permission behaviour per role, the production configuration, and the secret rotation.
