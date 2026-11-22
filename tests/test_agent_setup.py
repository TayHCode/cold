import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


COLD = Path(__file__).resolve().parents[1] / "cold"


class AgentSetupTest(unittest.TestCase):
    def test_missing_products_preview_and_apply_leave_home_untouched(self):
        with tempfile.TemporaryDirectory() as home:
            config = Path(home) / ".claude.json"
            original = b'{"mcpServers": {"existing": {"command": "keep-me"}}}\n'
            config.write_bytes(original)
            env = {"HOME": home, "PATH": os.defpath}
            for args in ([], ["--apply"]):
                with self.subTest(args=args):
                    output = subprocess.check_output([COLD, "agent-setup", *args], cwd=home, env=env)
                    for name in (b"Coldlocker", b"ColdRewind", b"Coldfix/ColdRecall"):
                        self.assertIn(name + b" unavailable", output)
                    self.assertEqual(list(Path(home).iterdir()), [config])
                    self.assertEqual(config.read_bytes(), original)

    def test_invalid_apply_arguments_leave_home_untouched(self):
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run([COLD, "agent-setup", "--apply", "--unexpected"], cwd=home,
                                    env={"HOME": home, "PATH": os.defpath}, capture_output=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(list(Path(home).iterdir()), [])

    def test_preview_then_apply_with_existing_client_hooks(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            package = home / "cold-tools/coldrewind/coldrewind"
            package.mkdir(parents=True)
            (package / "__init__.py").touch()
            (package / "init_cmd.py").write_text(
                '''import json
EVENTS = {"claude": ("PreToolUse",)}
def config_paths(home):
    return {"claude": home / ".claude/settings.json"}
def _read(path):
    return path.read_bytes()
def _plan_json(path, raw, client, install):
    config = json.loads(raw)
    groups = config["hooks"]["PreToolUse"]
    desired = [{"hooks": [{"command": "rewind"}]}]
    groups[:] = [group for group in groups if group not in desired] + desired
    return json.dumps(config)
''', encoding="utf-8")
            (package / "cli.py").write_text(
                '''from pathlib import Path
from . import init_cmd
def main(args):
    assert args == ["init", "--client", "claude"]
    path = init_cmd.config_paths(Path.home())["claude"]
    path.write_text(init_cmd._plan_json(path, path.read_bytes(), "claude", True))
''', encoding="utf-8")
            (package / "config.py").write_text(
                '''from pathlib import Path
class Registry:
    state_dir = Path.home()
    config_path = state_dir / "config.json"
    def _check_root(self, root):
        pass
    def roots(self):
        return (Path.cwd(),)
''', encoding="utf-8")
            (home / "registry.lock").touch()
            config = home / ".claude/settings.json"
            config.parent.mkdir()
            env = {"HOME": directory, "PATH": os.defpath}

            def setup(*args):
                return subprocess.check_output([COLD, "agent-setup", *args], cwd=home, env=env, text=True)

            def snapshot():
                return {path.relative_to(home): path.read_bytes() for path in home.rglob("*") if path.is_file()}

            recall = {"hooks": [{"command": "recall"}]}
            rewind = {"hooks": [{"command": "rewind"}]}
            config.write_text(json.dumps({"hooks": {"PreToolUse": [recall]}}))
            before = snapshot()
            self.assertIn(f"ColdRewind: would write {config}", setup())
            self.assertEqual(snapshot(), before)
            setup("--apply")
            self.assertEqual(json.loads(config.read_text()), {"hooks": {"PreToolUse": [recall, rewind]}})
            self.assertEqual(snapshot(), {**before, config.relative_to(home): config.read_bytes()})

            config.write_text(json.dumps({"hooks": {"PreToolUse": [rewind, recall]}}))
            before = snapshot()
            self.assertNotIn(f"ColdRewind: would write {config}", setup())
            self.assertEqual(snapshot(), before)
            setup("--apply")
            self.assertEqual(snapshot(), before)
