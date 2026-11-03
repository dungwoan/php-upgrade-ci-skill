# php-ci-upgrade

Agent skill: run a legacy PHP / CodeIgniter 3 (and mostly CI 2.2.6) upgrade end to end — to PHP 8.4 with 8.5 readiness, optionally swapping the CI 3.1.x core for the `hoangkim28/codeigniter` fork.

Covers: phase order and gates, PHP 8.4/8.5 deprecation and fatal patterns, the CI3 core fork swap, dead-feature removal, security sweep, Docker/infra bumps, and the PR/deploy checklist. Bundled upgrade docs (playbook + two real project lesson files) live in `references/upgrade-docs/`.

## Install

```bash
npx skills add dungwoan/php-upgrade-ci-skill
```

Or copy the folder into your skills directory:

```bash
git clone https://github.com/dungwoan/php-upgrade-ci-skill.git ~/.config/opencode/skills/php-ci-upgrade
```

## Layout

- `SKILL.md` — the skill itself (workflow, phases, gates)
- `references/` — per-topic detail (fork swap, dead features, security, Docker/infra, PHP 8.4/8.5 patterns, audit checklist, PR checklist, delegation prompts)
- `references/upgrade-docs/` — bundled team upgrade docs: `AI_AGENT_PLAYBOOK_PHP8.md`, `LESSONS_NAMABANK_PHP84.md`, `LESSONS_HANMIR_PHP84.md`, version tables
- `scripts/lint-gate.sh`, `scripts/sweep-patterns.sh` — the lint gate and deprecation sweep used by the workflow

## Note

`SKILL.md` sets `disable-model-invocation: true` (no auto-trigger), so the agent loads it only when invoked by name. Remove those frontmatter keys if you want it to auto-trigger from its description.
