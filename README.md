# Cold

Cold provides day-2 infrastructure you can run on hardware you own. Use it to checkpoint an agent’s changes, run CI in disposable VMs, and turn recurring failures into checks. The catalog lists each tool and where to get it.

## The loop

Coldbox records what ran in CI. Coldfix can turn recurring failures into proven checks, and Coldlocker makes rules available to connected agents. ColdRewind records local edits so the developer can inspect or undo a step.

## Tools

<!-- catalog:start -->
| Tool | What it does | Availability | Cold installs it |
|---|---|---|---|
| [Coldbox](https://github.com/TayHCode/coldbox) | Run CI jobs in disposable VMs on your own hardware. | public source | yes |
| [Coldcleaner](https://github.com/TayHCode/coldcleaner) | Preview disk cleanup and verify archives before deleting files. | public source | yes |
| [Coldlocker](https://github.com/TayHCode/coldlocker) | Share skills, rules, hooks and MCP across agents. | public source | yes |
| [Coldfix](https://github.com/TayHCode/coldfix) | Scan for recurring agent mistakes and rerun proofs from the lesson library. | public source | yes |
| [Coldvault](https://github.com/TayHCode/coldvault) | Search a local vault of agent conversations and repository notes. | public source | yes |
| [Coldpass](https://coldpass.dev) | Browse public README trial results and run evidence. | web only | no |
| [Coldrelease](https://github.com/TayHCode/coldrelease) | Scan and verify an export before making it public. | public source | yes |
| [Coldverify](https://github.com/TayHCode/coldverify) | Replay an observed failure and its fix across two revisions. | public source | yes |
| [Coldguardian](https://github.com/TayHCode/coldguardian) | Check approved home networks for changes and risky services. | public source | yes |
| [ColdRewind](https://github.com/TayHCode/coldrewind) | Checkpoint a workspace and restore local files and Git state. | public source | yes |
| Coldcontribute | Find contribution opportunities requested by maintainers. | parked | no |
<!-- catalog:end -->

For agent discovery, see [tools.json](tools.json), [llms.txt](llms.txt) and
[llms-full.txt](llms-full.txt). Edit `tools.json` and run
`python3 render_catalog.py` to regenerate the standalone installer catalog, this table and the text indexes.

## Install and manage tools

Once the website serves this revision, preview the install on Linux with this command.

```sh
curl -fsSL https://coldstack.dev/install.sh | sh
```

It prints the checkout and launcher changes and leaves the destinations untouched.
To apply, run these commands in the directory where you will keep the installer.

```sh
curl -fsSLo install.sh https://coldstack.dev/install.sh
sh install.sh --apply
```

Clone this repository using GitHub’s **Code** menu. From the checkout, run `./cold list` to see product availability and install support. Running `./cold` with no arguments previews a full install. A preview leaves the checkout and launcher destinations untouched.

```sh
./cold list
./cold
./cold install coldvault
./cold install coldvault --apply
```

Apply installs the named tools and a `cold` launcher. Keep the umbrella clone in place because the launcher calls its `install.sh`. The default checkout directory is `~/cold-tools` and the default launcher directory is `~/.local/bin`. To override them, export `COLD_HOME` and `COLD_BIN` for all lifecycle commands. Put the launcher directory on your `PATH`.

```sh
cold status
cold doctor --json
cold update coldvault
cold uninstall coldvault
```

`status` shows each tool supported by the installer and its installed revision. `doctor` checks installed tools and reports incomplete installs. `update` fast-forwards installed checkouts, either all of them or the names supplied. `uninstall` takes exactly one tool and requires both a marked launcher and a checkout with the expected origin. It refuses checkouts with local work, including ignored files. Generated Python bytecode caches for source files in the checkout can be removed along with the tool. Other tools, the umbrella launcher, and configuration outside the checkout stay in place.

`cold doctor --json` emits one object with `schema_version: 1`, a top-level `status`, and a `tools` array. Each tool reports whether its launcher runs (`launcher_healthy`) and whether the current PATH resolves that launcher (`shell_visible`). Exit 0 means `healthy`, exit 1 means `problem`, and exit 2 means `error` with an `error` message. A missing PATH entry, a shadowed launcher, or an install with no tools yields exit 1. Git credential prompts are disabled when stdin is not a terminal.

The installer uses Bash, Git and the `python3` on your PATH. For a full install, use Python 3.14 or newer because Coldcleaner requires it. For a selective install, use Python 3.12 or newer and meet the selected tool’s requirements. Apply also needs the name `cold` in the launcher directory. If another program owns that name, choose a separate `COLD_BIN`. Use `./install.sh` to preview supported tools, `./install.sh --apply` to install them and `./install.sh --check` to check them.

Follow each public tool's README for standalone installation and prerequisites. Coldbox's host install (`sudo ./install.sh`) needs Incus.

## Set up agent clients

From the workspace you want ColdRewind to watch, run `cold agent-setup` to
preview the client settings, hooks, and workspace registration. Add `--apply`
to make the changes.

```sh
cold agent-setup
cold agent-setup --apply
```

Coldlocker connects to configured Claude Code, Codex, and OpenCode clients over
MCP. Its hook installer adds the Stop hook and, when ColdRecall is available,
adds its context hook for Claude Code and Codex. ColdRewind registers the
current workspace and installs hooks for detected clients.

The helper uses existing checkouts named `coldlocker`, `coldrewind`, and
`coldfix` under `COLD_HOME`. The public Coldlocker checkout supports MCP
connections. To add Stop and ColdRecall hooks, use a Coldlocker checkout that
includes `hooks/install.py`. The preview reports missing products and clients.

## Limitations

- `install.sh` is a Bash script for Linux and macOS. It doesn't run on Windows outside WSL.
- It clones each supported tool's default branch over the network. `--check` reports the installed commit.
- It doesn't install each tool's own dependencies or host setup, such as Incus for Coldbox.

## How they work together

Coldbox writes a receipt for every CI job. Coldfix reads it and turns failures into lessons. ColdRecall and Coldlocker deliver those lessons to agents. Coldvault gives agents search over past work. Coldpass tests public READMEs, and Coldrelease gates what goes public.

For the receipt format, import command and hook interfaces, see [docs/how-it-works.md](docs/how-it-works.md).

## License

MIT. See [LICENSE](LICENSE).
