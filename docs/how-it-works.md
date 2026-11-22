# How the Cold tools connect

The [tool catalog](../tools.json) lists each product's availability and install support. The interfaces below describe what a user can run from the public repositories.

## 1. Coldbox receipt to Coldfix

- **Producer:** Coldbox.
- **Consumer:** Coldfix.
- **Format:** one JSON file per VM at `/var/lib/coldbox/receipts/<id>.json`, with the raw log beside it as `<id>.log`.
- **Import command:** `coldfix ingest --format coldbox --input RECEIPT.json`. Coldfix groups recurring failures. To prove a lesson, supply a check that fails on the original revision and passes on the fixed revision.

Coldbox writes `coldbox.receipt/v1`. Use `repo` and `sha` to identify the checkout, `mode` to distinguish runner, local and ad-hoc jobs, and `verdict`, `cause` and `reason_code` to interpret the outcome.

| Verdict | How to read it |
|---|---|
| `pass` | Runner and local jobs completed successfully with evidence that tests ran. An ad-hoc command exited 0. |
| `fail` | A check, job command or isolation check failed. |
| `refused` | Admission or verification profile rules refused the job. |
| `canceled` | GitHub canceled the runner job. |
| `idle` | The runner VM stopped without a job. |
| `incomplete` | Coldbox could not establish an outcome, confirm teardown or establish that tests ran where required. |

`checks[]` records each command, status, exit and duration. A check after a failure can have status `not_run` (older receipts used `skipped`). `tests_ran` excludes skipped tests. When JUnit results are available, `tests` contains counts and per-test outcomes. Read `tests.truncated` before using the detailed list. [Coldbox receipt format](https://github.com/TayHCode/coldbox/blob/main/docs/receipt.md)

## 2. Flaky-test detection

- **Producer:** Coldbox receipts and CI attempt records.
- **Consumer:** Coldfix.
- **Command:** `coldfix flaky` prints stored flaky failures with their passing and failing attempts as JSON.

For per-test comparisons across Coldbox runner receipts, group by `github.repo`, `github.sha`, `github.workflow` and `job_name`. Use `github.run_id` and `github.run_attempt` to distinguish attempts. Compare the status for the same suite, class and test name. Omit ambiguous duplicate results and truncated lists. The Coldfix command groups stored CI attempts by repository, revision, job and check. [Coldbox comparison rules](https://github.com/TayHCode/coldbox/blob/main/docs/receipt.md#flaky-tests) · [Coldfix](https://github.com/TayHCode/coldfix)

## 3. Coldlocker hook and MCP

- **Producer:** Coldlocker. It keeps a local catalog of skills, routines and rules.
- **Consumers:** agent clients connected over MCP.
- **Commands:** `python3 hub.py scan --json` shows the inventory. `python3 hub.py connect --agent claude codex` previews client configuration from a Coldlocker checkout.

Coldfix can export proven lessons as Markdown or deliver them to a Coldlocker rules repository. The public Coldlocker checkout supports MCP. Automatic Stop and recall hook installation requires a checkout that includes the hook installer. [Coldlocker](https://github.com/TayHCode/coldlocker) · [Setup guide](../README.md#set-up-agent-clients)

## 4. ColdRecall hook and ColdRewind

From the Coldfix checkout, `python3 coldrecall.py hook` reads an agent event on stdin and returns matching lesson context. The hook fails open. `python3 coldrecall.py lookup --path FILE` looks up lessons for a file, and `python3 coldrecall.py compile` rebuilds the lookup table from proof records.

ColdRewind captures files and Git state around an agent edit. Inspect the recorded step with `coldrewind log` and `coldrewind diff STEP`. From the workspace to be captured, `cold agent-setup` previews the client and workspace changes. [ColdRewind](https://github.com/TayHCode/coldrewind)

## 5. Coldvault search interface

- **Producer:** the local Coldvault index of imported conversations and project notes.
- **Consumers:** people and agents querying the vault.
- **Command:** `python3 coldvault.py search TERM --vault VAULT --json`.

On exit 0 or 1 the response contains `schema_version: 1` and a `hits` array. Each hit has a vault-relative path, line number and text. Source, repository, authorship and trust metadata can also be present. Exit 1 means no matches. Exit 2 returns an error object. [Coldvault JSON contract](https://github.com/TayHCode/coldvault/blob/main/docs/vault.md#cli-json)

## 6. Coldrelease gate

- **Producer:** Coldrelease.
- **Consumer:** the owner reviewing a candidate for public release.
- **Format:** `release-check.json` declares quickstart commands, checks, exclusions and reviewed findings.
- **Steps:** scan the source, export a clean tree, run the declared commands, then validate the receipt against the export and policy used for verification.

The receipt binds the export head, tree and verification inputs. A stale or mismatched receipt fails validation. Only a passing export can proceed to approval. Making a repository public is a separate owner action. [Coldrelease workflow](https://github.com/TayHCode/coldrelease/blob/main/docs/coldrelease-workflow.md)

## 7. Coldpass

Coldpass publishes public README trial results with their run evidence. Use the website to inspect individual results or its JSON index to read them programmatically. The trial runner is private. [Coldpass](https://coldpass.dev) · [Public results index](https://coldpass.dev/api/v1/index.json)

## 8. Tools with separate responsibilities

- **Coldbox and Coldcleaner.** `coldbox reap` retires expired job VMs and receipts. Coldcleaner previews cleanup candidates and checks archive evidence before deleting eligible files under its configured rules. [Coldcleaner](https://github.com/TayHCode/coldcleaner)
- **Coldbox and Coldverify.** Coldverify can replay a failure across revisions and run a repository's test recipe. Its verification receipt describes the evidence for a change. A Coldbox job receipt describes the VM job that ran it. [Coldverify receipts](https://github.com/TayHCode/coldverify/blob/main/docs/verify-receipt.md)
- **Coldguardian.** It monitors the networks you configure and reports changes. `coldguardian status --json` validates its configuration without starting a scan. [Coldguardian](https://github.com/TayHCode/coldguardian)
- **Coldcontribute.** Work is parked. There is no public checkout or install command.
