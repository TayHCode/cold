# Cold — Agent Guide

Safety: Never pass `--apply` or `--yes`, and never run `cold update` or `cold uninstall`, without explicit user approval. `install.sh`, `cold install`, and `cold agent-setup` preview by default; `cold update` and `cold uninstall` modify or delete checkouts immediately.

## First command & install
1. Preview the catalog: `./cold list` (or after install: `cold list`).
2. Preview install (no changes): `curl -fsSL https://coldstack.dev/install.sh | sh` or `./cold install <tool>`.
3. Apply only after user approval: `curl -fsSL https://coldstack.dev/install.sh | sh -s -- --apply` or `./cold install <tool> --apply`.
4. Preview agent client setup: `cold agent-setup` (add `--apply` only after user approval).

## Verify
- `cold doctor --json` — schema version 1 check of installed launchers and `PATH`.
- `cold status --json` — schema version 1 status of all catalog tools (`installed`, `not installed`, `incomplete or foreign`).

## Exit codes
- `0`: healthy / at least one tool installed (`status`), or preview/command succeeded.
- `1`: problem — nothing installed, missing `PATH` entry, shadowed/broken launcher, or refused conflict.
- `2`: usage error, unknown tool, or missing prerequisite (`git` / `python3`) / runtime error.

## Discovery & privacy
No telemetry. Network: fetching install.sh from coldstack.dev (when using the curl one-liner) and git clone/pull from github.com/coldstack-dev only. Machine-readable catalog: `tools.json`, `llms.txt`, `llms-full.txt`.
