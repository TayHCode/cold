#!/usr/bin/env bash
set -uo pipefail

install=$(cd "$(dirname "$0")/.." && pwd)/install.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tools='coldbox coldcleaner coldlocker coldfix coldvault coldrelease coldverify coldguardian coldrewind'
passed=0
failed=0

ok() {
    if "${@:2}"; then
        passed=$((passed + 1))
        printf 'ok   %s\n' "$1"
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n' "$1"
    fi
}

contains() { grep -qF -- "$2" <<< "$1"; }
count() { grep -cE -- "$2" <<< "$1"; }
equals() { [ "$1" = "$2" ]; }
quiet() { "$@" >/dev/null 2>&1; }

clean_path=
IFS=: read -r -a entries <<< "$PATH"
for entry in "${entries[@]}"; do
    for tool in $tools; do
        [ -e "$entry/$tool" ] && continue 2
    done
    clean_path=${clean_path:+$clean_path:}$entry
done
export PATH=$clean_path

home=$work/home
bin=$work/bin
cd "$work" || exit 1
export COLD_HOME=$home COLD_BIN=$bin

out=$("$install" 2>&1); status=$?
ok 'preview exits 0' equals "$status" 0
ok 'preview prints 9 clones' equals "$(count "$out" '^\+ git clone ')" 9
ok 'preview prints 9 command writes' equals "$(count "$out" "^\\+ write ")" 9
ok 'preview writes nothing' test ! -e "$home" -a ! -e "$bin"

out=$("$install" --check 2>&1); status=$?
ok 'check before install fails' equals "$status" 1
ok 'check before install reports 9 FAIL lines' equals "$(count "$out" ' FAIL not installed')" 9

out=$("$install" --apply 2>&1); status=$?
ok 'apply exits 0' equals "$status" 0
ok 'apply says not on PATH' contains "$out" "$bin is not on PATH"

out=$(PATH="$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'check after install exits 0' equals "$status" 0
for tool in $tools; do
    version=$(git -C "$home/$tool" describe --tags --always)
    ok "check prints $tool path and version" contains "$out" "$bin/$tool  version $version  OK"
    ok "command -v $tool resolves to the link" equals "$(PATH="$bin:$PATH" command -v "$tool")" "$bin/$tool"
done
ok 'check on PATH prints no PATH note' equals "$(count "$out" 'not on PATH')" 0

out=$("$install" --check 2>&1); status=$?
ok 'check off PATH exits 1' equals "$status" 1
ok 'check off PATH says so' contains "$out" "$bin is not on PATH"

ln -s "$bin" "$work/binlink"
out=$(PATH="$work/binlink:$PATH" "$install" --check 2>&1); status=$?
ok 'check with a symlinked PATH entry exits 0' equals "$status" 0

mkdir "$work/cwd" && cd "$work/cwd" && mkdir coldcleaner && printf 'raise SystemExit(9)\n' > coldcleaner/__main__.py
ok 'coldcleaner ignores a same-named package in cwd' quiet "$bin/coldcleaner" --help
cd "$work" || exit 1

out=$("$install" --apply 2>&1); status=$?
ok 'second apply exits 0' equals "$status" 0

out=$(COLD_HOME=home COLD_BIN=relbin "$install" --apply 2>&1); status=$?
ok 'apply with relative COLD_HOME and COLD_BIN exits 0' equals "$status" 0
cd "$work/cwd" || exit 1
ok 'relative install runs from another directory' quiet "$work/relbin/coldvault" --help
ok 'relative install runs coldcleaner from another directory' quiet "$work/relbin/coldcleaner" --help
cd "$work" || exit 1
out=$(COLD_HOME=home COLD_BIN=relbin "$install" --check 2>&1); status=$?
ok 'relative check prints the absolute command path' contains "$out" "$work/relbin/coldvault  version"
rm -rf "$work/relbin"

mkdir -p "$work/shadow" && printf '#!/bin/sh\n' > "$work/shadow/coldbox" && chmod 755 "$work/shadow/coldbox"
out=$(PATH="$work/shadow:$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'shadowed command fails check' equals "$status" 1
ok 'shadowed command is named' contains "$out" "FAIL shadowed by $work/shadow/coldbox"

printf 'mine\n' > "$work/victim"
refuses() {
    local label=$1 dir=$2 target=$3
    out=$(COLD_BIN=$dir "$install" --apply 2>&1); status=$?
    ok "$label: apply exits 1" equals "$status" 1
    ok "$label: apply names the file" contains "$out" "Refusing to replace $dir/$target"
    ok "$label: no other command written" equals "$(find "$dir" -mindepth 1 | wc -l)" 1
    ok "$label: victim unchanged" equals "$(cat "$work/victim")" mine
}
mkdir "$work/foreign" && printf 'mine\n' > "$work/foreign/coldvault"
refuses 'foreign file' "$work/foreign" coldvault
ok 'foreign file: file unchanged' equals "$(cat "$work/foreign/coldvault")" mine
mkdir "$work/symlink" && ln -s "$work/victim" "$work/symlink/coldlocker"
refuses 'symlink to file' "$work/symlink" coldlocker
mkdir "$work/ourlink" && ln -s "$bin/coldbox" "$work/ourlink/coldbox"
refuses 'symlink to our command' "$work/ourlink" coldbox
mkdir "$work/dangling" && ln -s "$work/missing" "$work/dangling/coldbox"
refuses 'dangling symlink' "$work/dangling" coldbox
ok 'dangling symlink: target not created' test ! -e "$work/missing"
mkdir -p "$work/directory/coldrelease"
refuses 'directory' "$work/directory" coldrelease

ln -sf "$work/victim" "$bin/coldvault"
out=$(PATH="$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'symlinked command fails check' equals "$status" 1
ok 'symlinked command reported not installed' contains "$out" "FAIL not installed"
rm "$bin/coldvault"
"$install" --apply >/dev/null 2>&1

git -C "$home/coldvault" checkout -q --detach
out=$(PATH="$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'detached checkout still checks OK' equals "$status" 0
ok 'detached checkout reports its commit' contains "$out" "version $(git -C "$home/coldvault" describe --tags --always)  OK"
git -C "$home/coldvault" checkout -q -

mv "$home/coldrelease" "$work/coldrelease.moved"
out=$(PATH="$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'missing checkout fails check' equals "$status" 1
ok 'missing checkout reports unknown version and FAIL' contains "$out" "$bin/coldrelease  version unknown  FAIL coldrelease --help failed"
git -C "$work" init -q && git -C "$work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m parent
mkdir "$home/coldrelease"
out=$(PATH="$bin:$PATH" "$install" --check 2>&1); status=$?
ok 'non-git checkout inside another repo fails check' equals "$status" 1
ok 'non-git checkout reports unknown, not the parent commit' contains "$out" "$bin/coldrelease  version unknown  FAIL"
rmdir "$home/coldrelease"
mv "$work/coldrelease.moved" "$home/coldrelease"

mkdir "$work/killgit"
cat > "$work/killgit/git" <<EOF
#!/bin/sh
if [ "\$1" = clone ]; then mkdir -p "\$3/.git"; kill -9 \$\$; fi
exec "$(command -v git)" "\$@"
EOF
chmod 755 "$work/killgit/git"
mv "$home/coldvault" "$work/coldvault.moved"
out=$(PATH="$work/killgit:$PATH" "$install" --apply 2>&1); status=$?
ok 'killed clone stops apply' test "$status" -ne 0
ok 'killed clone leaves no tool directory' test ! -e "$home/coldvault"
out=$("$install" --apply 2>&1); status=$?
ok 'apply after a killed clone exits 0' equals "$status" 0
ok 'apply after a killed clone installs a working tool' quiet "$bin/coldvault" --help
ok 'apply after a killed clone leaves no partial clone' equals "$(find "$home" -mindepth 1 -maxdepth 1 -name '.*' | wc -l)" 0
rm -rf "$work/coldvault.moved"

mkdir -p "$work/foreignhome/coldlocker" && printf 'mine\n' > "$work/foreignhome/coldlocker/notes"
out=$(COLD_HOME=$work/foreignhome COLD_BIN=$work/foreignbin "$install" --apply 2>&1); status=$?
ok 'non-checkout tool directory: apply exits 1' equals "$status" 1
ok 'non-checkout tool directory: apply names it' contains "$out" "Refusing to use $work/foreignhome/coldlocker: it is not a git checkout"
ok 'non-checkout tool directory: nothing else written' equals "$(find "$work/foreignhome" -mindepth 1 | wc -l)" 2
ok 'non-checkout tool directory: no commands written' test ! -e "$work/foreignbin"
ok 'non-checkout tool directory: file unchanged' equals "$(cat "$work/foreignhome/coldlocker/notes")" mine

git init -q "$work/brokenhome/coldbox"
out=$(COLD_HOME=$work/brokenhome COLD_BIN=$work/brokenbin "$install" --apply 2>&1); status=$?
ok 'clone with no commit: apply exits 1' equals "$status" 1
ok 'clone with no commit: apply names it' contains "$out" "Refusing to use $work/brokenhome/coldbox: it is not a git checkout"

out=$("$install" --bogus 2>&1); status=$?
ok 'unknown argument exits 2' equals "$status" 2
out=$("$install" --check --apply 2>&1); status=$?
ok 'two arguments exit 2' equals "$status" 2

printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
