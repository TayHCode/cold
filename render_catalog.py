import argparse
import json
from pathlib import Path
import shlex


ROOT = Path(__file__).resolve().parent
START = "<!-- catalog:start -->\n"
END = "<!-- catalog:end -->"


ENTRIES = {
    "coldbox": "coldbox",
    "coldcleaner": "-m coldcleaner",
    "coldlocker": "hub.py",
    "coldfix": "coldfix.py",
    "coldvault": "vault_kit.py",
    "coldrelease": "release_check.py",
    "coldverify": "coldverify",
    "coldguardian": "-m coldguardian.cli",
    "coldrewind": "-m coldrewind.cli",
}


def main():
    parser = argparse.ArgumentParser(description="Regenerate the README catalog and agent indexes.")
    parser.add_argument("--check", action="store_true", help="Check for stale generated files.")
    args = parser.parse_args()
    tools = json.loads((ROOT / "tools.json").read_text(encoding="utf-8"))["tools"]
    rows = []
    table = [
        "| Tool | What it does | Availability | Cold installs it |",
        "|---|---|---|---|",
    ]
    index = [
        "# Cold Stack",
        "",
        "See [tools.json](tools.json) for machine-readable discovery and",
        "[llms-full.txt](llms-full.txt) for command and output details.",
        "",
    ]
    full = [
        "# Cold Stack tool reference",
        "",
        "In an authorized umbrella checkout, run `./cold list` to see availability and install",
        "support. Run `./cold install TOOL` to preview or add `--apply` to install.",
        "Run `cold doctor --json` for schema version 1 launcher and PATH checks. Exit 0 means",
        "healthy, 1 means a problem and 2 means an error.",
        "",
        "The tool entries below describe public interfaces where available.",
    ]
    for tool in tools:
        name = tool["name"]
        url = tool["url"]
        link = f"[{name}]({url})" if url else name
        availability = tool["availability"]
        supported = "yes" if tool["cold_install"] else "no"
        entry = ENTRIES[tool["id"]] if tool["cold_install"] else ""
        rows.append("|".join((tool["id"], availability, url or "", entry)))
        capability = tool["capability"]
        table.append(f"| {link} | {capability} | {availability} | {supported} |")
        index.append(f"- {link} ({availability}, cold install: {supported}). {capability}")
        full.extend(["", f"## {name}", "", f"{capability} Availability: {availability}. Cold install: {supported}."])
        if tool["install"]:
            full.append(f"Install with `{tool['install']}`. Run `{tool['id']} --help` for commands.")
        if url:
            full.append(f"See [{name} documentation]({url}) for setup and usage.")
        full.extend(tool[key] for key in ("json", "agent_entrypoints") if tool[key])

    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    before, old_table = readme.split(START, 1)
    _, after = old_table.split(END, 1)
    installer = (ROOT / "install.sh").read_text(encoding="utf-8")
    prefix, catalog = installer.split("\ncatalog=", 1)
    _, body = catalog.split("\n\n", 1)
    outputs = {
        "README.md": before + START + "\n".join(table) + "\n" + END + after,
        "install.sh": prefix + "\ncatalog=" + shlex.quote("\n".join(rows)) + "\n\n" + body,
        "llms.txt": "\n".join(index) + "\n",
        "llms-full.txt": "\n".join(full) + "\n",
    }
    stale = []
    for name, content in outputs.items():
        path = ROOT / name
        if args.check:
            if not path.is_file() or path.read_bytes() != content.encode("utf-8"):
                stale.append(name)
        else:
            path.write_bytes(content.encode("utf-8"))
    if stale:
        parser.exit(1, f"Run python3 render_catalog.py to regenerate: {', '.join(stale)}\n")


if __name__ == "__main__":
    main()
