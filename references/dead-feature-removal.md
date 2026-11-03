# Dead-feature removal before or during an upgrade (Phase 5)

Removing a dead feature is cheaper than porting it to PHP 8, and it shrinks the audit. It is also where a careless `git rm` breaks a live page. This file says how to decide, how to prove there are no callers, what lives outside the repo, and in what order to remove things.

## Contents

1. The decision rule
2. Evidence checklist (commands)
3. Database-side dependencies
4. Removal order
5. Commit plan and notes
6. The candidate table (ask before any delete)
7. Things that look dead and are not
8. Examples from the reference run

## 1. The decision rule

| Finding | Action |
|---|---|
| Feature has a live caller: route in use, menu item, cron, JS call, DB document | Keep. Port the PHP 8 fixes |
| Feature has no caller in code, routes, views, JavaScript, cron, CI, or DB documents | Candidate for removal. Ask the user (section 6) |
| Feature has no caller in code but a DB document still references it (widget, menu, permission) | Not removable until the DB side is switched off. Put the DB steps in the pre-deploy checklist |
| Feature is a vendored library nobody loads | Candidate. Check `require`, `load->library`, and autoload before deciding |
| Feature is a sample or demo asset (CKEditor samples, demo pages) | Candidate. Low risk, but ask anyway; some are scanned by audit tools |

"Nothing calls it" is not enough. The check is "nothing reachable calls it", which includes the database.

## 2. Evidence checklist (commands)

Set the name you are checking, then run each command. Record the result (zero or the list of hits) in the candidate table.

```bash
NAME="ChatModule"         # class name, controller name, route segment, view name, or config key
ROUTE="chat"              # URL segment used by the feature

# 1. Code references, excluding the feature's own files (set FEATURE_DIRS to them)
grep -rn "$NAME" --include='*.php' --include='*.js' --include='*.html' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.xml' --include='*.crontab' --include='*.sh' . 2>/dev/null | grep -v "^./vendor/" | head -50

# 2. Routes that point at it
grep -n "$ROUTE" application/config/routes.php 2>/dev/null

# 3. Menus and permissions in code (often built from DB documents, so also check section 3)
grep -rn "$ROUTE" application/views application/controllers application/libraries 2>/dev/null | head -50

# 4. Views loaded by name
grep -rn "load->view(.*$NAME\|parser->parse(.*$NAME" application 2>/dev/null

# 5. Cron and scheduler, CI, container files
grep -rn "$NAME" cronjob .gitlab-ci.yml Dockerfile docker* .devcontainer 2>/dev/null   # adjust to the project's cron, CI and container paths
```

For the feature's own controllers, also list the URL the controller exposes. CodeIgniter maps `application/controllers/x/Y.php` to `x/y/<method>`. Those URLs are the things to search for in JavaScript and in DB documents.

Note the `grep ... | head` in command 1 truncates output. Re-run without `head` before you conclude "zero". Zero hits in the first 50 is not zero.

Do not stop at "the grep found nothing". Two things a plain grep misses:

- URLs built at run time from a variable (`base_url($segment)`). Search the segment name, not the full URL.
- Views rendered through a template name stored in the database (widgets, navigator entries). That is section 3.

## 3. Database-side dependencies

In the reference run, widgets, menus, permissions and scheduled tasks lived in MongoDB and changed outside git. If the app keeps any of these in a database, handle the database side first: a code removal that leaves the database pointing at the deleted code breaks pages.

Check the collections the app reads for references to the feature's names, views, routes or permission keys. In the reference run these were:

| Document kind (example) | What references the feature | What breaks if the code goes first |
|---|---|---|
| Widget | `name` holds a view file name (for example a chat status or messenger widget) placed in a header position | Every page render calls `parser->parse` on a missing view, and the page returns 500 until the widget cache expires |
| Navigator / menu | Menu items pointing at removed routes | Menu links return 404 (noisy, not fatal) |
| Module / permission | Permission strings naming removed routes | Permission screens show dead entries; admins may grant access to a removed page |
| Scheduled task | A job that calls a removed controller or command | Job fails every run, and the scheduler may keep retrying |
| Collection that only the feature used | Data written by the removed code | Nothing, until someone drops the data; drop only after a backup and a human decision |

Checks against the live data (run by the DB owner, read-only first):

- Widgets: find documents whose name matches a removed view file. Note their `_id`, active flag, and position key. Do not paste the documents into chat if they hold personal data.
- Menus and permissions: find entries whose route strings match the removed routes.
- Scheduled tasks: find entries whose command matches a removed controller.

The repo cannot change any of this. Write the steps into the pre-deploy checklist (`pr-and-deploy-checklist.md`), with the document kinds, the key names, and the order.

## 4. Removal order

Remove in this order so that no step leaves a live reference. Each step is its own commit.

1. **Switch off entry points in the data.** Deactivate widgets, hide menu items, remove scheduled tasks. This is an ops step and must happen before the deploy that removes the view. Clear the cache that holds the widget list (example: a 120-second TTL, or the specific key). Do not use an admin "clear cache" that deletes logs.
2. **Remove routes and menus in code.** Remove the route entries, navigation config, and menu definitions that point at the feature.
3. **Remove controllers and API endpoints.**
4. **Remove views and templates** that only those controllers loaded, and the JavaScript that calls them.
5. **Remove models, libraries and config** that only the removed code used. Check `application/config` for keys nothing reads now.
6. **Remove composer packages** that only the removed code used, then regenerate the lock (`composer update <pkg>` for each removed package, or remove and `composer update --lock`). Verify with `composer validate`.
7. **Remove static assets last**, or leave them and list them as follow-ups (the reference run left some vendor demo pages and a map script in place; they were not loaded).
8. **Update the notes** in the same commit or the next one.

After each commit: run the lint gate, and grep for the removed names again. The grep must show zero live references.

## 5. Commit plan and notes

- One commit per feature for the code, and one "Update upgrade notes for removed <feature>" commit (the reference run's pattern). Notes must say: what was removed, the commit, what the DB must do, what was not verified.
- Use `git rm` for tracked files, not `rm`, so the history records the decision.
- Never delete a file in the same commit as an unrelated fix. A reviewer must see the deletion on its own.
- Do not rewrite history to remove a feature from it.

Example message: `Remove dead chat detail links` (the reference run's style: a short imperative subject, no prefix). Use the project's own style.

## 6. The candidate table (ask before any delete)

Get the user's confirmation for each row before you `git rm`. Show the evidence, not an opinion.

```markdown
| Feature | Files (count and key paths) | Callers in code | Routes or menus | DB dependency | Proposed action | Confirmed |
|---|---|---|---|---|---|---|
| Chat module | 14 000+ files under chat_module/ (vendored chat UI) | none outside the module | 3 routes, 2 menu items | widget document, 1 menu document | remove after DB steps | pending |
| Google login | 4 controllers, 2 libraries, 1 config | none | 1 route | none | remove | pending |
```

The "Files" column should use counts with a few key paths, not the full list, unless the user asks for it.

## 7. Things that look dead and are not

- A controller that is only reached by a cron calling it over HTTP. Check the crontab and the scheduler. Those are live.
- A library loaded by a hook (`hooks/*.php`) or autoload. Grep the hooks and `application/config/autoload.php`.
- A view loaded through `load->view()` with a variable name. Grep for the file name without its folder.
- A helper called from a template (`templates/*`). Grep the helper function name.
- Code inside `vendor/` or `third_party/` that a copied library calls. Check its own internal references.
- Code guarded by a config flag that is off in production but on in the staging environment. Check every environment file, not only the production one (and never print their values).
- Code only called from the CLI (`php index.php ...`). The web grep will not find it. Grep the cron and CLI directories (in the reference run, `cronjob` and `third_party/cli`) and any shell scripts.

## 8. Examples from the reference run

These are what was done in that project, for calibration. They are not instructions for another project.

- Chat module (a large vendored tree) and its status endpoints were removed in one commit, after the widget document that rendered its header panel was switched off.
- Google login was first replaced by a library and then removed when the code path was shown to be unreachable: a call to methods that did not exist meant the login flow never reached its end.
- Google Maps location views were removed; the unused map script was left as a follow-up.
- A test harness controller that sent SMS and read card transactions with no login check was removed (a removal, not a gate, because nothing called it).
- Secrets found in removed files stayed in git history and were passed to ops for rotation.
