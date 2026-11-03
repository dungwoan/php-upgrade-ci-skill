# Delegation prompts

These templates name roles, not agents. Map each role to whatever agents or sessions you have, or play every role yourself, one after another.

| Role | Does | Edits code? |
|---|---|---|
| Coordinator (you) | Runs the phases, talks to the user, hands out the prompts below, checks what comes back (section 9) | Only integration and notes |
| Researcher | Read-only audit and plan (template 2) | No |
| Implementor | One themed change on a fixed file list (templates 3 to 7) | Yes, and commits when told |
| Challenger (optional) | Tries to break a decision before a delete, a core swap or a deploy (template 8) | No |

Copy a template, fill the `<placeholders>`, and hand it to whoever takes that role. Assume the receiver starts with no context, so every prompt carries the constraints and the output format. Working alone, use the templates as checklists and skip the hand-off fields. Templates below: a shared header, then one per role or task.

## Contents

1. Shared header (paste into every prompt)
2. Researcher prompt: read-only audit
3. Implementor prompt: sweep one theme
4. Implementor prompt: infrastructure change
5. Implementor prompt: dead-feature removal (approved list only)
6. Implementor prompt: login-gate fix (approved list only)
7. Implementor prompt: notes update
8. Challenger prompt: challenge a decision
9. Checking what comes back

## 1. Shared header

Paste this block at the top of every prompt.

```text
Project root: <ABSOLUTE PATH>
Branch: <BRANCH> (do not switch branches)
Target runtime: PHP <TARGET> (lint must also pass on <NEXT_TARGET> where stated)
Skill dir (<SKILL_DIR> below): <ABSOLUTE PATH OF THE php-ci-upgrade SKILL FOLDER>
Run PHP with: <COMMAND, e.g. docker run --rm -v "$PWD:/src:ro" -w /src php:<TARGET>-cli php>
Commit style: <THE PROJECT'S STYLE FROM git log, with one example subject>
Reference (read first): <SKILL_DIR>/references/upgrade-docs/AI_AGENT_PLAYBOOK_PHP8.md (bundled default; use the team's newer playbook path if the user gave one, or "none")

Hard rules:
- Do not push. Do not force anything. Do not rewrite git history.
- Do not delete any tracked file unless the task text names it. Never delete without showing the file first.
- Never print the value of a secret, token, password or key. Report file paths and key names only.
- Only edit the files in your ownership list. If you need another file, stop and report it.
- Do not change business logic. Compatibility fixes only. Report suspected business bugs; do not fix them.
- Do not touch production systems. Use staging or local containers only.
- Run PHP only with the "Run PHP with" command above. Do not install PHP or anything else on the host.
- Commit only when the task says so, one theme per commit, in the commit style above. Do not stage files outside your ownership list.

Ownership (files you may edit): <LIST OR GLOB>
```

## 2. Researcher prompt: read-only audit

```text
[SHARED HEADER]

Task: read-only audit of this project for a PHP <TARGET> upgrade. Edit nothing. Create no files in the repo.

Do this, in order:
1. Phase 0 inventory: the seven items in <SKILL_DIR>/references/audit-checklist.md section 2 (framework version, core source, patched core files, core extensions, packages, error counts, extensions used versus present in the image).
2. Run the hazard sweep: <SKILL_DIR>/scripts/sweep-patterns.sh <project-root> and read the samples. Filter false positives (comment lines, JS template literals, vendored code behind function_exists) and say which filter you applied.
3. Run the lint gate from the project root: <SKILL_DIR>/scripts/lint-gate.sh <TARGET> <dirs> and <SKILL_DIR>/scripts/lint-gate.sh <NEXT_TARGET> <dirs>, listing only paths that exist. Include the full output summary, not just pass or fail.
4. Enumerate every controller and its login gate, using the commands in <SKILL_DIR>/references/security-sweep.md section 2. List endpoints with no gate, grouped by likely class.
5. Check the error configuration in every place (image ini, index.php, env bootstrap, .htaccess).

Return:
- A status table: Done, Partial, Not done, Unclear. Every row has evidence (file:line, or the command and its result). Anything you could not verify is Unclear, with the command that would settle it.
- Counts after filters, with raw counts in parentheses.
- A list of decisions the user must make.
- A "not verified" list.
Do not invent numbers. If a command failed, say so and show the error.
```

## 3. Implementor prompt: sweep one theme

```text
[SHARED HEADER]

Task: fix the "<THEME>" hazard across the files listed below, for PHP <TARGET>.
Theme reference: <SKILL_DIR>/references/php84-85-patterns.md, entry <ENTRY ID, e.g. D1>.
Pattern (grep): <REGEX FROM THE REFERENCE>

Files in scope (ownership): <FILE LIST OR GLOB>

Steps:
1. Run the grep on the files in scope. Read each hit. Count it as a fix only when it really is the hazard (not in a comment, not guarded, not JS).
2. Apply the fix from the reference. Keep the change minimal. Do not reformat unrelated lines.
3. Re-run the grep on the same files. The count must drop by exactly the number you changed. Report both numbers.
4. Lint the changed files from the project root: <SKILL_DIR>/scripts/lint-gate.sh <TARGET> <changed files>. It must print GATE PASS. Without Docker, lint each file twice with the "Run PHP with" command (-d short_open_tag=0, then =1, plus -d display_errors=1 -d error_reporting=-1 -l); the output must be only "No syntax errors detected" lines.
5. Commit in the commit style from the header: a subject naming the theme, and a body listing the count before and after.

Return: the commit hash (or "not committed"), before and after counts, the list of hits you did NOT change and why, and the lint output.
```

## 4. Implementor prompt: infrastructure change

```text
[SHARED HEADER]

Task: infrastructure change for PHP <TARGET>. Scope: <Dockerfile | php.ini and conf.d | .htaccess | CI config>.
Reference: <SKILL_DIR>/references/infra-and-docker.md, sections <N>.

Known constraints (confirm each before you change anything):
- Image tag: pin the exact patch release given in the task. Do not change the tag without it.
- Error policy: production shows no errors on screen, all errors go to the log. Screen output only behind an explicit debug flag.
- Do not remove any line that a writer rewrites (grep the writers first; report them).
- Extensions: add an extension only if you found a caller in code. Report the caller.

Steps:
1. Read the current file(s) in full.
2. Make the change in the smallest form that meets the task.
3. Build the image if the change is in the Dockerfile: docker build -t <local-tag> . (no push). Run php -v and php -m inside the built image and save the output tail.
4. For ini or .htaccess: show the effective setting inside the container (php -i | grep ...) and say which file wins.
5. Do not push. Do not run the deploy job. Commit in the commit style from the header, if the task says to commit.

Return: diff summary, the built image's php -v and php -m output (trimmed), the list of writers and callers you checked, and anything you could not verify.
```

## 5. Implementor prompt: dead-feature removal (approved list only)

```text
[SHARED HEADER]

Task: remove the features listed below. This list was approved by the user. Remove nothing else.

Approved list (feature, files):
<FEATURE A: list of files or glob>
<FEATURE B: list of files or glob>

Steps, per feature:
1. Re-verify the evidence: grep the feature's names (class, controller, route segment, view, config key) across code, JavaScript, routes, cron, CI and Docker files. Exclude the feature's own files. If you find a live caller, STOP that feature and report it. Do not remove it.
2. Remove with `git rm` (tracked files only). Do not use `rm` for tracked files.
3. Remove only the routes, menu entries and config keys that point at this feature, in the same commit.
4. Grep again for the names. Zero live references is the requirement.
5. Lint the project from its root: <SKILL_DIR>/scripts/lint-gate.sh <TARGET> <dirs that exist>. It must print GATE PASS.
6. Commit in the commit style from the header (subject like "Remove <feature>"). One feature per commit. Then a notes commit if the task says so.

Database-side steps are NOT yours. List them in the return value with document kinds and key names only (no document contents).

Return: per feature, the evidence (grep counts after removal), commit hash, lint output summary, and the database steps required. Name anything you stopped on.
```

## 6. Implementor prompt: login-gate fix (approved list only)

```text
[SHARED HEADER]

Task: add the login gate to the controllers listed below. Login only, no permission logic.
Reference: <SKILL_DIR>/references/security-sweep.md sections 5 and 6.

Approved list (controller path, endpoints, classification):
<PATH> | <methods> | gate
<PATH> | <methods> | keep public (reason)

Steps:
1. For each "gate" row: read the constructor. Insert the gate after parent::__construct(), using exactly the calls the app's gated base controller makes:
   <GATE CODE copied from the base controller's constructor. Reference run: $this->load->library('session'); $this->load->library('authentication'); $this->authentication->check_login();>
   Keep the rest of the original constructor unchanged and in order.
2. Make helper methods private or protected only where the task says so. Do not change any other visibility.
3. Check for self-calls: grep the project for the controller's URL (base_url or literal path) in hooks, libraries, helpers and JavaScript. If something calls it without a session, STOP and report it; do not gate it.
4. Lint the changed files with the target runtime.
5. Commit in the commit style from the header (subject like "Require login for <group>").

Do not change "keep public" rows. Do not add a JSON 401 branch unless the task says so.

Return: the list of files changed, each gate inserted (file:line), any self-call found, and the lint output.
```

## 7. Implementor prompt: notes update

```text
[SHARED HEADER]

Task: update the project's upgrade notes file (<PATH>) to match the code as it is now.

Steps:
1. Read the notes file and the commit list since the baseline: git log --oneline <BASELINE>..HEAD.
2. For each behaviour change in the commits, make sure the notes say: what changed, which commit, what the DB or ops must do, and what was not tested.
3. For each name the notes mention (class, route, file), grep it. Remove or correct any name that no longer exists in the code. Do not invent names.
4. Do not record any secret value. Name the key only.
5. Commit in the commit style from the header (subject like "Update upgrade notes").

Return: a list of corrections made, names you checked that are missing from the code, and anything in the notes you could not verify.
```

## 8. Challenger prompt: challenge a decision

Use this before a delete, a core swap, or a deploy decision. The challenger's job is to find the hole, not to agree.

```text
[SHARED HEADER]

Task: challenge the decision below. Assume it is wrong and look for evidence that it is. Read the code; do not edit anything.

Decision: <ONE SENTENCE>
Claimed evidence: <LIST, as the proposer gave it>

For each claimed piece of evidence:
- Re-run the check yourself. Report whether it holds.
- Look for the case the check misses: a URL built at run time, a database-held name, a CLI-only caller, a hook, a template name, a vendored copy.

Return:
- A verdict: Holds, Holds with conditions, or Does not hold.
- Each objection with the file:line or command that supports it.
- The one check that would settle it if you could not decide.
```

## 9. Checking what comes back

A delegate's claim is a claim, and so is an earlier step of your own when you work alone. Before you repeat it to the user:

1. Rerun the lint gate yourself on the branch: `<SKILL_DIR>/scripts/lint-gate.sh <TARGET> <dirs>`. Read the output.
2. `git status --porcelain` and `git log --oneline -<n>`: confirm the commits exist and that nothing unexpected is staged or changed.
3. `git diff --stat <BASELINE>..HEAD` for the files in scope. Anything outside the ownership list is a problem.
4. Rerun the sweep count for the theme. The count must match what the delegate reported.
5. If the delegate says a check passed, look at its output. "Passed" with no output is not evidence.

If a delegate stopped on a rule (a live caller found, a self-call, an unexpected file), that is a success of the process. Take the stop to the user as a decision.
