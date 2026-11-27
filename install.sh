#!/bin/sh
{
catalog='coldbox|public source|https://github.com/coldstack-dev/coldbox|coldbox
coldcleaner|public source|https://github.com/coldstack-dev/coldcleaner|-m coldcleaner
coldlocker|public source|https://github.com/coldstack-dev/coldlocker|hub.py
coldfix|public source|https://github.com/coldstack-dev/coldfix|coldfix.py
coldvault|public source|https://github.com/coldstack-dev/coldvault|vault_kit.py
coldpass|web only|https://coldpass.dev|
coldrelease|public source|https://github.com/coldstack-dev/coldrelease|release_check.py
coldverify|public source|https://github.com/coldstack-dev/coldverify|coldverify
coldguardian|public source|https://github.com/coldstack-dev/coldguardian|-m coldguardian.cli
coldrewind|public source|https://github.com/coldstack-dev/coldrewind|-m coldrewind.cli
coldcontribute|parked||'

if [ -n "${BASH_SOURCE:-}" ] && [ "$BASH_SOURCE" != "$0" ]; then return 0; fi

exec bash -c 'IFS= read -rd "" installer <&3; eval "$installer"' "$0" "$catalog" "$@" 3<<'COLD_INSTALLER'
exec 3<&-
catalog=$1
shift
set -euo pipefail

usage() {
    printf '%s\n' 'cold [install [TOOL ...] [--apply]]' 'cold list | status [--json] | doctor [--json]' \
        'cold update [TOOL ...] | uninstall TOOL' 'cold agent-setup [--apply]' 'install.sh [--apply | --check]'
}

doctor_error() {
    if [ "$json" = yes ]; then
        printf '{"schema_version":1,"status":"error","tools":[],"error":"%s"}\n' "$1"
    else
        printf '%s\n' "$1" >&2
    fi
    exit 2
}

bad_args() {
    if [ "$json" = yes ]; then doctor_error "Invalid $mode arguments"; fi
    usage >&2
    exit 2
}

mode=preview
json=no
case ${1-} in
    '') ;;
    install) shift ;;
    --apply) [ "$#" = 1 ] || bad_args; mode=apply; shift ;;
    --check) [ "$#" = 1 ] || bad_args; mode=check; shift ;;
    update) mode=update; shift ;;
    uninstall) [ "$#" = 2 ] || bad_args; mode=uninstall; shift ;;
    list) [ "$#" = 1 ] || bad_args; mode=$1; shift ;;
    status)
        mode=status
        shift
        if [ "${1-}" = --json ]; then json=yes; shift; fi
        [ "$#" = 0 ] || bad_args
        ;;
    agent-setup)
        mode=agent-setup
        shift
        if [ "${1-}" = --apply ]; then mode=agent-apply; shift; fi
        [ "$#" = 0 ] || bad_args
        ;;
    doctor)
        mode=doctor
        shift
        if [ "${1-}" = --json ]; then json=yes; shift; fi
        [ "$#" = 0 ] || bad_args
        ;;
    -h|--help) usage; exit 0 ;;
    *) bad_args ;;
esac

if [ "$mode" = list ]; then
    printf 'tool\tavailability\tcold_install\turl\n'
fi
tools=
while IFS='|' read -r name availability url entry; do
    supported=no
    if [ -n "$entry" ]; then
        supported=yes
        tools+=${tools:+$'\n'}"$name $url.git $entry"
    fi
    if [ "$mode" = list ]; then
        printf '%s\t%s\t%s\t%s\n' "$name" "$availability" "$supported" "$url"
    fi
done <<< "$catalog"
if [ "$mode" = list ]; then exit 0; fi

selected=
for arg in "$@"; do
    if [ "$arg" = --apply ] && [ "$mode" = preview ]; then
        mode=apply
        continue
    fi
    row=
    while read -r name repo entry; do
        if [ "$arg" = "$name" ]; then row="$name $repo $entry"; break; fi
    done <<< "$tools"
    if [ -z "$row" ]; then printf 'Unknown tool: %s\n' "$arg" >&2; exit 2; fi
    if ! grep -qxF "$row" <<< "$selected"; then
        selected=${selected}${selected:+"
"}${row}
    fi
done
if [ -n "$selected" ]; then tools=$selected; fi
for command in git python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        if [ "$mode" = doctor ] || [ "$mode" = check ] || [ "$json" = yes ]; then
            doctor_error "Required command not found: $command"
        fi
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

if [ "$mode" = preview ] || [ "$mode" = apply ] || [ "$mode" = check ]; then
    while read -r name minimum; do
        if ! grep -q "^$name " <<< "$tools"; then continue; fi
        if found=$(python3 -I -c 'import sys
print("%d.%d" % sys.version_info[:2])
sys.exit(sys.version_info < tuple(map(int, sys.argv[1].split("."))))' "$minimum"); then continue; fi
        reason="it needs Python $minimum or newer and python3 is $found"
        if [ -n "$selected" ]; then
            printf 'Cannot install %s: %s\n' "$name" "$reason" >&2
            exit 1
        fi
        printf 'Skipping %s: %s\n' "$name" "$reason"
        tools=$(grep -v "^$name " <<< "$tools")
    done <<< 'coldcleaner 3.14
coldverify 3.12'
fi

if [ ! -t 0 ]; then
    export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=false
fi

cold_home=${COLD_HOME:-"$HOME/cold-tools"}
cold_bin=${COLD_BIN:-"$HOME/.local/bin"}
case $cold_home in /*) ;; *) cold_home=$PWD/$cold_home ;; esac
case $cold_bin in /*) ;; *) cold_bin=$PWD/$cold_bin ;; esac

agent_rewind() {
    if [ ! -f "$cold_home/coldrewind/coldrewind/cli.py" ]; then
        printf 'ColdRewind unavailable (no checkout at %s)\n' "$cold_home/coldrewind"
        return
    fi
    python3 -IB - "$cold_home/coldrewind" "$mode" <<'PY'
import json
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from coldrewind import init_cmd
from coldrewind.cli import main
from coldrewind.config import Registry

paths = init_cmd.config_paths(Path.home())
args = []
detected = False
try:
    for client, path in paths.items():
        client_dir = path.parent.parent if client == "opencode" else path.parent
        if not client_dir.is_dir():
            print(f"ColdRewind: skip {path} ({client} not detected)")
            continue
        detected = True
        if client == "opencode":
            raw = init_cmd._read(path)
            change = init_cmd._plan_plugin(path, raw, True)
            events = "tool.execute.before, tool.execute.after"
        else:
            path = path.resolve()
            raw = init_cmd._read(path)
            change = init_cmd._plan_json(path, raw, client, True)
            events = ", ".join(init_cmd.EVENTS[client])
            if change is not None and raw is not None:
                current = json.loads(raw).get("hooks", {})
                wanted = json.loads(change)["hooks"]
                for event in init_cmd.EVENTS[client]:
                    group = wanted[event][-1]
                    existing = current.get(event, [])
                    if group in existing:
                        existing.remove(group)
                        existing.append(group)
                if current == wanted:
                    change = None
        if change is not None:
            args.extend(("--client", client))
            backup = " with backup" if raw is not None else ""
            print(f"ColdRewind: would write {path}{backup} ({events})")

    if detected:
        registry = Registry()
        root = Path.cwd().resolve()
        registry._check_root(root)
        register = root not in registry.roots()
        if register:
            print(f"ColdRewind: would register {root} in {registry.config_path}")
        lock = registry.state_dir / "registry.lock"
        if (args or register) and not lock.exists():
            print(f"ColdRewind: would create {lock}")
        if sys.argv[2] == "agent-apply":
            if args:
                sys.exit(main(["init", *args]))
            if register:
                registry.register(root)
except (OSError, ValueError) as error:
    sys.exit(f"ColdRewind: {error}")
PY
}

agent_setup() {
    local locker=$cold_home/coldlocker recall=$cold_home/coldfix/coldrecall.py
    agent_rewind
    if [ ! -f "$locker/hub.py" ]; then
        printf 'Coldlocker unavailable (no checkout at %s)\n' "$locker"
        printf 'Coldfix/ColdRecall unavailable (needs Coldlocker)\n'
        return
    fi
    printf 'Coldlocker MCP\n'
    set --
    if [ "$mode" = agent-apply ]; then set -- --write --yes; fi
    python3 -B "$locker/hub.py" connect --agent claude codex opencode "$@"
    if [ ! -f "$locker/hooks/install.py" ]; then
        printf 'Coldlocker hooks and ColdRecall unavailable (missing %s)\n' "$locker/hooks/install.py"
        return
    fi
    set --
    if [ "$mode" = agent-apply ]; then set -- --write; fi
    if [ -f "$recall" ]; then
        local recall_command
        recall_command=$(python3 -IB -c 'import shlex, sys; print(shlex.join([sys.executable, "-B", sys.argv[1], "hook"]))' "$recall")
        printf 'Coldfix/ColdRecall on UserPromptSubmit and PreToolUse: %s\n' "$recall_command"
        set -- "$@" --recall-command "$recall_command"
    else
        printf 'Coldfix/ColdRecall unavailable (missing %s)\n' "$recall"
    fi
    printf 'Coldlocker Stop and configured recall hooks\n'
    python3 -B "$locker/hooks/install.py" "$@"
}

if [[ "$mode" = agent-* ]]; then agent_setup; exit; fi

marker='# Written by cold install.sh'

ours() {
    [ -f "$1" ] && [ ! -L "$1" ] && grep -qxF "$marker" "$1"
}

on_path() {
    case ":$PATH:" in *":$cold_bin:"*) return 0 ;; esac
    return 1
}

launcher() {
    local dir=$1 entry=$2
    case $entry in
        -m\ *) printf 'PYTHONPATH=%q exec python3 -P %s "$@"\n' "$dir" "$entry" ;;
        *.py) printf 'exec python3 %q "$@"\n' "$dir/$entry" ;;
        *) printf 'exec %q "$@"\n' "$dir/$entry" ;;
    esac
}

launcher_body() {
    printf '#!/usr/bin/env bash\n%s\n' "$marker"
    launcher "$1" "$2"
}

launcher_matches() {
    ours "$1" && [ "$(cat "$1")" = "$(launcher_body "$2" "$3")" ]
}

origin_after_organization_move() {
    local origin
    origin=$(git -C "$1" config --local --get-all remote.origin.url) || return
    printf '%s\n' "${origin/#https:\/\/github.com\/TayHCode\//https://github.com/coldstack-dev/}"
}

checkout_state() {
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        echo absent
    elif [ ! -L "$1" ] && [ -d "$1/.git" ] && [ ! -L "$1/.git" ] &&
        [ "$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$1" && pwd -P)" ] &&
        git -C "$1" rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 &&
        [ "$(origin_after_organization_move "$1")" = "$2" ]; then
        echo ready
    else
        echo foreign
    fi
}

missing_pair() {
    [ ! -e "$1" ] && [ ! -L "$1" ] && [ ! -e "$2" ] && [ ! -L "$2" ]
}

check() {
    local failed=0 checked=no installed=0 incomplete=0 name repo entry dir link found version status state healthy visible
    while read -r name repo entry; do
        dir=$cold_home/$name
        link=$cold_bin/$name
        if [ "$mode" = doctor ] && missing_pair "$dir" "$link"; then continue; fi
        checked=yes
        state=$(checkout_state "$dir" "$repo")
        version=unknown
        if [ "$state" = ready ]; then
            if ! version=$(git -C "$dir" describe --tags --always); then
                check_message="Could not read version for $name"
                if [ "$json" = no ]; then printf '%s\n' "$check_message" >&2; fi
                return 2
            fi
        fi
        healthy=false
        visible=false
        found=
        if [ "$mode" = status ]; then
            if missing_pair "$dir" "$link"; then
                status='not installed'
            elif [ "$state" = ready ] && [ -x "$link" ] && launcher_matches "$link" "$dir" "$entry"; then
                status=installed
                installed=$((installed + 1))
            else
                status='incomplete or foreign'
                incomplete=$((incomplete + 1))
            fi
        else
            if found=$(command -v "$name") && [ "$found" -ef "$link" ] && [ -x "$found" ]; then
                visible=true
            fi
            if ! ours "$link"; then
                status='FAIL not installed; run ./install.sh --apply'
            elif [ "$state" = foreign ]; then
                status="FAIL unexpected checkout at $dir"
            elif [ "$state" != ready ] || ! launcher_matches "$link" "$dir" "$entry" || ! PYTHONDONTWRITEBYTECODE=1 "$link" --help </dev/null >/dev/null 2>&1; then
                status="FAIL $name --help failed"
            else
                healthy=true
                if [ "$visible" = true ]; then
                    status=OK
                elif [ -n "$found" ]; then
                    status="FAIL shadowed by $found"
                else
                    status="FAIL $cold_bin is not on PATH; add it to PATH"
                fi
            fi
        fi
        case $status in FAIL*) failed=1 ;; esac
        if [ "$json" = yes ]; then
            printf '%s\0' "$name" "$link" "$version" "$status" "$healthy" "$visible"
            continue
        fi
        printf '%-12s %s  version %s  %s\n' "$name" "$link" "$version" "$status"
    done <<< "$tools"
    if [ "$checked" = no ]; then
        check_message='No tools installed; run cold install TOOL --apply'
        if [ "$json" = no ]; then printf '%s\n' "$check_message"; fi
        return 1
    fi
    if [ "$mode" = status ]; then
        if [ "$installed" -eq 0 ] && [ "$incomplete" -eq 0 ]; then
            check_message='No tools installed; run cold install TOOL --apply'
            failed=1
        elif [ "$incomplete" -gt 0 ]; then
            failed=1
        fi
        if [ "$json" = no ]; then
            if [ -n "${check_message-}" ]; then printf '%s\n' "$check_message"; fi
            if ! on_path; then
                printf '%s is not on PATH. Open a new login shell or add it to PATH.\n' "$cold_bin"
            fi
        fi
    fi
    return "$failed"
}

if [ "$json" = yes ]; then
    rc=0
    path_ready=false
    if on_path; then path_ready=true; fi
    report=$(
        {
            result=0
            check_message=
            check || result=$?
            printf '%s\0' "$result" "$check_message"
        } | python3 -I -c 'import json, os, sys
mode, on_path = sys.argv[1], sys.argv[2] == "true"
*fields, code, message, _ = os.fsdecode(sys.stdin.buffer.read()).split("\0")
code = int(code)
rows = iter(fields)
if mode == "status":
    tools = [
        dict(name=name, path=path, version=version, status=status)
        for name, path, version, status, _, _ in zip(rows, rows, rows, rows, rows, rows, strict=True)
    ]
    installed = sum(1 for tool in tools if tool["status"] == "installed")
    if code == 2:
        top = "error"
    elif code == 0:
        top = "installed"
    elif installed == 0 and all(tool["status"] == "not installed" for tool in tools):
        top = "not_installed"
    else:
        top = "problem"
    report = dict(schema_version=1, status=top, installed_count=installed, on_path=on_path, tools=tools)
else:
    tools = [
        dict(name=name, path=path, version=version, status=status,
             launcher_healthy=healthy == "true", shell_visible=visible == "true")
        for name, path, version, status, healthy, visible in zip(rows, rows, rows, rows, rows, rows, strict=True)
    ]
    report = dict(schema_version=1, status=("healthy", "problem", "error")[code], tools=tools)
if message:
    report["error" if code == 2 else "message"] = message
print(json.dumps(report))
sys.exit(code)' "$mode" "$path_ready"
    ) || rc=$?
    if [ -z "$report" ]; then doctor_error "Could not generate $mode report"; fi
    printf '%s\n' "$report"
    exit "$rc"
fi
if [ "$mode" = check ] || [ "$mode" = status ] || [ "$mode" = doctor ]; then
    check_message=
    check
    exit
fi

preflight() {
    if [ "$cold_home" = "$cold_bin" ] || [ "$cold_home" -ef "$cold_bin" ]; then
        printf 'COLD_HOME and COLD_BIN must be different directories\n' >&2
        exit 1
    fi
    if { [ "$mode" = apply ] || [ "$mode" = preview ]; } &&
        { [ -e "$cold_bin/cold" ] || [ -L "$cold_bin/cold" ]; } && ! ours "$cold_bin/cold"; then
        printf 'Refusing to replace %s: it was not written by install.sh\n' "$cold_bin/cold" >&2
        exit 1
    fi
    while read -r name repo entry; do
        dir=$cold_home/$name
        link=$cold_bin/$name
        if [ "$mode" = update ] && [ -z "$selected" ] && missing_pair "$dir" "$link"; then continue; fi
        state=$(checkout_state "$dir" "$repo")
        if [ "$state" = foreign ]; then
            printf 'Refusing to use %s: it is not a git checkout of %s\n' "$dir" "$repo" >&2
            exit 1
        fi
        if { [ -e "$link" ] || [ -L "$link" ]; } && ! ours "$link"; then
            printf 'Refusing to replace %s: it was not written by install.sh\n' "$link" >&2
            exit 1
        fi
        if { [ "$mode" = update ] || [ "$mode" = uninstall ]; } &&
            { [ "$state" != ready ] || ! launcher_matches "$link" "$dir" "$entry"; }; then
            printf 'Refusing to %s %s: both an owned launcher and its checkout are required\n' "$mode" "$name" >&2
            exit 1
        fi
    done <<< "$tools"
}

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    if [ "$mode" = apply ]; then "$@"; fi
}

if [ "$mode" = apply ] || [ "$mode" = update ] || [ "$mode" = uninstall ]; then
    if [ ! -d "$cold_home" ] || [ ! -d "$cold_bin" ]; then
        preflight
        if [ "$mode" != apply ]; then exit 0; fi
        mkdir -p "$cold_home" "$cold_bin"
    fi
    exec 8<"$cold_home" 9<"$cold_bin"
    # The shell retains these open file descriptions after Python takes the locks.
    python3 - <<'PYLOCK'
import fcntl
import os

directories = {}
for fd in (8, 9):
    stat = os.fstat(fd)
    directories[stat.st_dev, stat.st_ino] = fd
for key in sorted(directories):
    fcntl.flock(directories[key], fcntl.LOCK_EX)
PYLOCK
fi
preflight

if [ "$mode" = update ]; then
    while read -r name repo _; do
        if missing_pair "$cold_home/$name" "$cold_bin/$name"; then continue; fi
        git -C "$cold_home/$name" remote set-url origin "$repo"
        git -C "$cold_home/$name" pull --ff-only origin
    done <<< "$tools"
    exit
fi
clean_for_uninstall() {
    git -C "$1" status --porcelain=v1 -z --untracked-files=all --ignored |
        python3 -I -c 'import os, sys
from importlib.util import source_from_cache
from pathlib import Path

for row in sys.stdin.buffer.read().split(b"\0"):
    if not row:
        continue
    cache = Path(sys.argv[1]) / os.fsdecode(row[3:])
    if row[:3] not in (b"?? ", b"!! ") or cache.suffix != ".pyc" or cache.is_symlink() or not cache.is_file():
        sys.exit(1)
    try:
        source = Path(source_from_cache(str(cache)))
    except ValueError:
        sys.exit(1)
    with cache.open("rb") as stream:
        header = stream.read(16)
    if not source.is_file() or len(header) != 16 or header[2:4] != b"\r\n":
        sys.exit(1)' "$1"
}

if [ "$mode" = uninstall ]; then
    read -r name _ <<< "$tools"
    dir=$cold_home/$name
    case "$(cd "$cold_bin" && pwd -P)/" in
        "$(cd "$dir" && pwd -P)/"*) printf 'Refusing to remove checkout containing COLD_BIN\n' >&2; exit 1 ;;
    esac
    local_refs=$(git -C "$dir" rev-list -1 --all --not --remotes=origin)
    if ! clean_for_uninstall "$dir" || [ -n "$local_refs" ] || ! git -C "$dir" symbolic-ref -q HEAD >/dev/null ||
        [ -d "$dir/.git/worktrees" ]; then
        printf 'Refusing to remove %s with local work or linked worktrees\n' "$dir" >&2
        exit 1
    fi
    rm -rf -- "$dir"
    rm -- "$cold_bin/$name"
    printf 'Uninstalled %s\n' "$name"
    exit
fi

cleanup() {
    if [ ! -L "$stage" ] && [ "$stage" -ef /dev/fd/6 ]; then
        rm -rf -- "$stage"
    fi
    if [ -n "${bin_stage-}" ] && [ ! -L "$bin_stage" ] && [ "$bin_stage" -ef /dev/fd/7 ]; then
        rm -rf -- "$bin_stage"
    fi
}

if [ "$mode" = apply ]; then
    stage=$(mktemp -d "$cold_home/.cold-install.XXXXXXXX")
    exec 6<"$stage"
    bin_stage=
    trap cleanup 0
    trap 'exit 1' HUP INT TERM
    bin_stage=$(mktemp -d "$cold_bin/.cold-install.XXXXXXXX")
    exec 7<"$bin_stage"
else
    run mkdir -p "$cold_home" "$cold_bin"
    stage="$cold_home/<staging>"
fi
while read -r name repo entry; do
    dir=$cold_home/$name
    link=$cold_bin/$name
    case $(checkout_state "$dir" "$repo") in
        ready)
            run git -C "$dir" remote set-url origin "$repo"
            run git -C "$dir" pull --ff-only origin
            ;;
        absent)
            run git clone "$repo" "$stage/$name"
            run mv "$stage/$name" "$dir"
            ;;
        *) printf 'Refusing unexpected checkout at %s\n' "$dir" >&2; exit 1 ;;
    esac
    printf '+ write %q: %s\n' "$link" "$(launcher "$dir" "$entry")"
    if [ "$mode" = apply ]; then
        launcher_body "$dir" "$entry" > "$bin_stage/$name"
        chmod 755 "$bin_stage/$name"
        mv "$bin_stage/$name" "$link"
    fi
    run "$link" --help
    if [ "$mode" = apply ]; then printf 'Installed %s\n' "$name"; fi
done <<< "$tools"

printf '+ install CLI %q\n' "$cold_bin/cold"
if [ "$mode" = apply ]; then
    {
        printf '#!/usr/bin/env bash\n%s\nset -- %q "$@"\n' "$marker" "$catalog"
        printf '%s\n' "IFS= read -rd '' installer <<'COLD_INSTALLER'"
        # shellcheck disable=SC2154
        printf '%sCOLD_INSTALLER\n%s\n' "$installer" "eval \"\$installer\""
    } > "$bin_stage/cold"
    chmod 755 "$bin_stage/cold"
    mv "$bin_stage/cold" "$cold_bin/cold"
    printf '\nInstalled. Run cold status to see each tool.\n'
    if ! on_path; then
        printf '%s is not on PATH. Open a new login shell or add it to PATH.\n' "$cold_bin"
    fi
else
    printf '\nPreview only. Nothing was changed. Re-run with --apply.\n'
fi
COLD_INSTALLER
}
