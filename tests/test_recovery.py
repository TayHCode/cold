import csv
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest

INSTALL = Path(__file__).resolve().parents[1] / "install.sh"
TOOLS = {
    "coldbox": "coldbox",
    "coldcleaner": "coldcleaner/__main__.py",
    "coldlocker": "hub.py",
    "coldfix": "coldfix.py",
    "coldvault": "vault_kit.py",
    "coldrelease": "release_check.py",
    "coldverify": "coldverify",
    "coldguardian": "coldguardian/cli.py",
    "coldrewind": "coldrewind/cli.py",
}


class RecoveryTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.tools = self.root / "tools"
        self.bin = self.root / "bin"
        self.shims = self.root / "shims"
        self.shims.mkdir()
        self.env = dict(os.environ, HOME=tmp.name, COLD_HOME=str(self.tools),
                        COLD_BIN=str(self.bin), GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=str(self.root / "gitconfig"), GIT_ALLOW_PROTOCOL="file",
                        PATH=str(self.shims) + os.pathsep + os.environ["PATH"])
        self.git = shutil.which("git")
        catalog = json.loads(INSTALL.with_name("tools.json").read_text())
        self.urls = {tool["id"]: tool["url"] + ".git" for tool in catalog["tools"]
                     if tool["cold_install"]}
        for name, entry in TOOLS.items():
            repo = self.root / (name + ".git")
            self.cmd(self.git, "init", "-q", repo)
            file = repo / entry
            file.parent.mkdir(exist_ok=True)
            file.write_text("#!/bin/sh\nexit 0\n" if name in ("coldbox", "coldverify") else "pass\n")
            file.chmod(0o755)
            self.cmd(self.git, "-C", repo, "add", ".")
            self.cmd(self.git, "-C", repo, "-c", "user.name=test", "-c",
                     "user.email=fixture", "commit", "-qm", "fixture")
            self.cmd(self.git, "config", "--global", f"url.{repo}.insteadOf", self.urls[name])

    def cmd(self, *args, check=True):
        return subprocess.run(args, cwd=self.root, env=self.env, check=check,
                              capture_output=True, text=True, timeout=20)

    def apply(self, check=True):
        return self.cmd(INSTALL, "--apply", check=check)

    def test_apply_from_saved_website_script(self):
        saved = self.root / "saved copy" / "install.sh"
        saved.parent.mkdir()
        saved.write_bytes(INSTALL.read_bytes())
        self.cmd("sh", saved, "install", "coldvault", "--apply")
        self.assertIn("  installed", self.cmd(self.bin / "cold", "status").stdout)

    def shim(self, name, body):
        path = self.shims / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)
        return path

    def test_foreign_staging_survives(self):
        foreign = self.tools / ".coldbox.partial"
        foreign.mkdir(parents=True)
        (foreign / "keep").touch()
        self.apply()
        self.assertTrue((foreign / "keep").exists())

    def test_coincident_destinations_refused_before_clone(self):
        self.tools.mkdir()
        self.bin.symlink_to(self.tools, target_is_directory=True)
        result = self.apply(check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(self.tools.iterdir()), [])

    def test_foreign_checkout_never_runs(self):
        self.apply()
        dir = self.tools / "coldbox"
        self.cmd(self.git, "-C", dir, "remote", "set-url", "origin", self.root / "coldbox.git")
        (dir / "coldbox").write_text("#!/bin/sh\ntouch ran\n")
        self.cmd(self.git, "-C", dir, "-c", "user.name=test", "-c",
                 "user.email=fixture", "commit", "-qam", "foreign program")
        for mode in ("--check", "--apply"):
            result = self.cmd(INSTALL, mode, check=False)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertFalse((self.root / "ran").exists())

    def test_cleanup_preserves_replacement_directory(self):
        self.shim("git", 'if [ "$1" = clone ]; then\n'
                  '  stage=${3%/*}; mv "$stage" "$stage.moved"\n'
                  '  mkdir "$stage"; touch "$stage/keep"; exit 1\n'
                  'fi\n' + f'exec "{self.git}" "$@"\n')
        self.assertNotEqual(self.apply(check=False).returncode, 0)
        self.assertEqual(len(list(self.tools.glob(".cold-install.*/keep"))), 1)

    def test_interrupted_launcher_and_offline_retry(self):
        shim = self.shim("chmod", 'printf "#!" > "$2"\nkill -KILL "$PPID"\n')
        result = self.apply(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.bin / "coldbox").exists())
        shim.unlink()
        (self.root / "coldlocker.git").rename(self.root / "offline")
        result = self.apply(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([s for s in result.stdout.splitlines() if s.startswith("Installed ")],
                         ["Installed coldbox", "Installed coldcleaner"])
        (self.root / "offline").rename(self.root / "coldlocker.git")
        self.assertIn("Installed coldrelease", self.apply().stdout)
        link = self.bin / "coldbox"
        original = link.read_bytes()
        self.shim("chmod", 'printf "#!" > "$2"\nkill -KILL "$PPID"\n')
        self.assertNotEqual(self.apply(check=False).returncode, 0)
        self.assertEqual(link.read_bytes(), original)
        self.cmd(link, "--help")

    def test_competing_applies_during_interrupted_clone(self):
        self.shim("git", 'if [ "$1" = clone ] && mkdir first 2>/dev/null; then\n'
                  '  mkdir -p "$3"; touch "$3/started" waiting; exec sleep 30\n'
                  'fi\n' + f'exec "{self.git}" "$@"\n')
        first = subprocess.Popen([INSTALL, "--apply"], cwd=self.root, env=self.env,
                                 start_new_session=True, stdout=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 10
            while not (self.root / "waiting").exists():
                self.assertIsNone(first.poll())
                self.assertLess(time.monotonic(), deadline)
                time.sleep(.02)
            second = subprocess.Popen([INSTALL, "--apply"], cwd=self.root, env=self.env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    second.wait(timeout=1)
            finally:
                os.killpg(first.pid, signal.SIGKILL)
                first.wait(timeout=5)
                stdout, stderr = second.communicate(timeout=20)
            self.assertEqual(second.returncode, 0, stderr)
            self.assertIn("Installed coldrelease", stdout)
        finally:
            if first.poll() is None:
                os.killpg(first.pid, signal.SIGKILL)
                first.wait(timeout=5)

    def test_selective_lifecycle_from_path(self):
        cold = INSTALL.with_name("cold")
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        listing = self.cmd(cold, "list").stdout
        rows = csv.DictReader(listing.splitlines(), delimiter="\t")
        names = [row["tool"] for row in rows if row["cold_install"] == "yes"]
        self.assertEqual(names, list(TOOLS))
        self.assertEqual(self.cmd(cold).stdout.count("+ git clone "), len(names))
        preview = self.cmd(cold, "install", "coldvault").stdout
        self.assertEqual(preview.count("+ git clone "), 1)
        self.assertIn("coldvault.git", preview)
        self.assertFalse(self.tools.exists())
        self.assertFalse(self.bin.exists())
        self.bin.mkdir()
        other = self.bin / "unrelated"
        other.write_text("preserve me")
        self.cmd(cold, "install", "coldvault", "--apply")
        self.assertEqual({p.name for p in self.tools.iterdir()}, {"coldvault"})
        status = self.cmd("cold", "status").stdout
        self.assertIn("  installed", status)
        self.assertIn("  not installed", status)
        doctor = json.loads(self.cmd("cold", "doctor", "--json").stdout)
        self.assertEqual([(t["name"], t["status"]) for t in doctor["tools"]],
                         [("coldvault", "OK")])
        remote = self.root / "coldvault.git"
        self.cmd(self.git, "-C", remote, "-c", "user.name=test", "-c",
                 "user.email=fixture", "commit", "--allow-empty", "-qm", "new")
        self.cmd("cold", "update", "coldvault")
        checkout = self.tools / "coldvault"
        self.assertEqual(self.cmd(self.git, "-C", checkout, "rev-parse", "HEAD").stdout,
                         self.cmd(self.git, "-C", remote, "rev-parse", "HEAD").stdout)
        self.cmd("cold", "uninstall", "coldvault")
        self.assertFalse(checkout.exists())
        self.assertFalse((self.bin / "coldvault").exists())
        self.assertEqual(self.cmd("cold", "list").stdout, listing)
        self.assertEqual(other.read_text(), "preserve me")

    def test_doctor_json_with_closed_stdin(self):
        path = self.env["PATH"]
        ready_path = str(self.bin) + os.pathsep + path
        restricted = self.root / "restricted"
        restricted.mkdir()
        for name in ("bash", "dirname", "git", "python3"):
            (restricted / name).symlink_to(shutil.which(name))

        empty = self.cmd(INSTALL, "doctor", "--json", check=False)
        self.assertEqual(empty.returncode, 1, empty.stdout + empty.stderr)
        self.assertIn("No tools installed", json.loads(empty.stdout)["message"])

        self.env["PATH"] = ready_path
        self.cmd(INSTALL, "install", "coldvault", "--apply")
        cold = self.bin / "cold"
        launcher = self.bin / "coldvault"
        saved = launcher.with_suffix(".saved")
        for case, code, status, message in (
            ("healthy", 0, "healthy", "OK"),
            ("missing tool", 1, "problem", "not installed"),
            ("missing PATH", 1, "problem", "not on PATH"),
            ("missing Git", 2, "error", "git"),
            ("missing Python", 2, "error", "python3"),
            ("invalid arguments", 2, "error", "Invalid"),
            ("version read fails", 2, "error", "Could not read version for coldvault"),
        ):
            with self.subTest(case=case):
                args = [cold, "doctor", "--json"]
                env = dict(self.env)
                if case == "missing tool":
                    launcher.rename(saved)
                elif case == "missing PATH":
                    env["PATH"] = path
                elif case == "missing Git":
                    (restricted / "git").unlink()
                    env["PATH"] = str(restricted)
                elif case == "missing Python":
                    (restricted / "git").symlink_to(self.git)
                    (restricted / "python3").unlink()
                    env["PATH"] = str(restricted)
                elif case == "invalid arguments":
                    args.append("--invalid")
                elif case == "version read fails":
                    self.shim("git", 'if [ "$3" = describe ]; then exit 128; fi\n'
                              + f'exec "{self.git}" "$@"\n')
                try:
                    result = subprocess.run(args, cwd=self.root, env=env, stdin=subprocess.DEVNULL,
                                            capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                    report = json.loads(result.stdout)
                    self.assertEqual(report["schema_version"], 1)
                    self.assertEqual(report["status"], status)
                    if code == 2:
                        self.assertIn(message, report["error"])
                    else:
                        tool, = report["tools"]
                        self.assertEqual(tool["name"], "coldvault")
                        self.assertIn(message, tool["status"])
                        self.assertEqual(tool["launcher_healthy"], case != "missing tool")
                        self.assertEqual(tool["shell_visible"], case == "healthy")
                finally:
                    if case == "missing tool":
                        saved.rename(launcher)

    def test_unattended_clone_does_not_prompt_for_git_credentials(self):
        class RequiresCredentials(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="fixture"')
                self.end_headers()

            def log_message(self, *_args):
                pass

        askpass = self.shim("askpass", 'touch asked\nexit 1\n')
        self.env.update(GIT_ASKPASS=str(askpass), GIT_ALLOW_PROTOCOL="http",
                        GIT_TERMINAL_PROMPT="1")
        with ThreadingHTTPServer(("localhost", 0), RequiresCredentials) as server:
            self.cmd(self.git, "config", "--global", "--unset-all",
                     f"url.{self.root / 'coldvault.git'}.insteadOf")
            self.cmd(self.git, "config", "--global",
                     f"url.http://{server.server_address[0]}:{server.server_port}/.insteadOf",
                     self.urls["coldvault"])
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                result = subprocess.run([INSTALL, "install", "coldvault", "--apply"],
                                        cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
                                        capture_output=True, text=True, timeout=10)
            finally:
                server.shutdown()
                worker.join()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("terminal prompts disabled", result.stderr)
        self.assertFalse((self.root / "asked").exists())
        self.assertFalse((self.tools / "coldvault").exists())

    def test_refuse_unowned_or_incomplete_pair(self):
        self.cmd(INSTALL, "install", "coldvault", "--apply")
        cold = self.bin / "cold"
        link = self.bin / "coldvault"
        checkout = self.tools / "coldvault"
        launcher = link.read_bytes()
        link.write_text("foreign")
        for command in ("uninstall", "update"):
            self.assertNotEqual(self.cmd(cold, command, "coldvault", check=False).returncode, 0)
        self.assertTrue(checkout.exists())
        self.assertEqual(link.read_text(), "foreign")
        link.unlink()
        self.assertNotEqual(self.cmd(cold, "uninstall", "coldvault", check=False).returncode, 0)
        self.assertTrue(checkout.exists())
        link.write_bytes(launcher)
        self.cmd(self.git, "-C", checkout, "remote", "set-url", "origin", "elsewhere")
        self.assertNotEqual(self.cmd(cold, "uninstall", "coldvault", check=False).returncode, 0)
        self.assertTrue(checkout.exists())
        checkout.rename(self.root / "moved")
        self.assertNotEqual(self.cmd(cold, "uninstall", "coldvault", check=False).returncode, 0)
        self.assertEqual(link.read_bytes(), launcher)

    def test_selection_requires_catalog_names(self):
        for args in (("uninstall",), ("uninstall", "coldbox", "coldvault"),
                     ("install", "coldvault", "--apply", "../outside")):
            self.assertEqual(self.cmd(INSTALL, *args, check=False).returncode, 2)
        self.assertFalse(self.tools.exists())
        self.assertFalse(self.bin.exists())
        self.bin.mkdir()
        (self.bin / "cold").write_text("my command")
        self.assertNotEqual(self.cmd(INSTALL, "install", "coldbox", "--apply",
                                     check=False).returncode, 0)
        self.assertEqual((self.bin / "cold").read_text(), "my command")
        self.assertFalse(self.tools.exists())

    def test_uninstall_preserves_other_tools_and_local_work(self):
        self.cmd(INSTALL, "install", "coldbox", "coldvault", "--apply")
        self.cmd(INSTALL, "update")
        note = self.tools / "coldvault" / "notes"
        note.write_text("mine")
        self.assertNotEqual(self.cmd(INSTALL, "uninstall", "coldvault", check=False).returncode, 0)
        self.assertEqual(note.read_text(), "mine")
        self.cmd(INSTALL, "uninstall", "coldbox")
        self.assertEqual({p.name for p in self.tools.iterdir()}, {"coldvault"})
        self.assertEqual({p.name for p in self.bin.iterdir()}, {"coldvault", "cold"})

    def test_uninstall_preserves_ignored_data(self):
        self.cmd(INSTALL, "install", "coldvault", "--apply")
        checkout = self.tools / "coldvault"
        (checkout / ".git/info/exclude").write_text("data/\n")
        data = checkout / "data"
        data.mkdir()
        (data / "db").write_text("keep")
        result = self.cmd(INSTALL, "uninstall", "coldvault", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((data / "db").read_text(), "keep")
        self.assertTrue((self.bin / "coldvault").is_file())

    def test_launcher_must_target_selected_checkout(self):
        self.cmd(INSTALL, "install", "coldvault", "--apply")
        link = self.bin / "coldvault"
        original = link.read_bytes()
        other_home = self.root / "second"
        other_home.mkdir()
        self.cmd(self.git, "clone", self.urls["coldvault"],
                 other_home / "coldvault")
        self.env["COLD_HOME"] = str(other_home)
        for action in ("update", "uninstall"):
            result = self.cmd(INSTALL, action, "coldvault", check=False)
            self.assertNotEqual(result.returncode, 0, action)
            self.assertEqual(link.read_bytes(), original)
            self.assertTrue((other_home / "coldvault" / ".git").is_dir())

    def test_used_python_tool_can_be_uninstalled(self):
        self.env.pop("PYTHONDONTWRITEBYTECODE", None)
        self.env.pop("PYTHONPYCACHEPREFIX", None)
        self.cmd(INSTALL, "install", "coldcleaner", "--apply")
        self.cmd(self.bin / "coldcleaner")
        self.cmd(self.bin / "cold", "uninstall", "coldcleaner")
        self.assertFalse((self.tools / "coldcleaner").exists())
        self.assertFalse((self.bin / "coldcleaner").exists())

    def test_lifecycle_accepts_previous_launcher(self):
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        self.cmd(INSTALL, "install", "coldvault", "--apply")
        link = self.bin / "coldvault"
        entry = self.tools / "coldvault" / "vault_kit.py"
        path = self.cmd("bash", "-c", 'printf %q "$1"', "_", entry).stdout
        link.write_text('#!/usr/bin/env bash\n# Written by cold install.sh\n'
                        f'exec python3 {path} "$@"\n')
        self.cmd(self.bin / "cold", "doctor")
        self.cmd(self.bin / "cold", "update", "coldvault")
        self.cmd(self.bin / "cold", "uninstall", "coldvault")
        self.assertFalse(link.exists())

    def test_used_legacy_module_with_existing_cache(self):
        self.env.pop("PYTHONDONTWRITEBYTECODE", None)
        self.env.pop("PYTHONPYCACHEPREFIX", None)
        self.cmd(INSTALL, "install", "coldcleaner", "--apply")
        checkout = self.tools / "coldcleaner"
        link = self.bin / "coldcleaner"
        path = self.cmd("bash", "-c", 'printf %q "$1"', "_", checkout).stdout
        link.write_text('#!/usr/bin/env bash\n# Written by cold install.sh\n'
                        f'PYTHONPATH={path} exec python3 -P -m coldcleaner "$@"\n')
        self.cmd(link)
        cache = next(checkout.rglob("__main__.*.pyc"))
        local = cache.parent / "local.pyc"
        local.write_bytes(b"keep")
        (checkout / ".git/info/exclude").write_text("__pycache__/\n")
        self.assertNotEqual(self.cmd(INSTALL, "uninstall", "coldcleaner", check=False).returncode, 0)
        self.assertEqual(local.read_bytes(), b"keep")
        local.unlink()
        self.cmd(INSTALL, "uninstall", "coldcleaner")
        self.assertFalse(link.exists())
        self.assertFalse(checkout.exists())
