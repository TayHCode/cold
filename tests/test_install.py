import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("install_test.sh")


class InstallTest(unittest.TestCase):
    def test_website_pipe_previews_without_writes(self):
        installer = SCRIPT.parent.parent / "install.sh"
        with tempfile.TemporaryDirectory() as home:
            env = {"HOME": home, "PATH": os.defpath}
            expected = subprocess.check_output([installer], cwd=home, env=env)
            self.assertIn(b"+ git clone ", expected)
            self.assertEqual(
                expected.splitlines()[-1],
                b"Preview only. Nothing was changed. Re-run with --apply.",
            )
            for shell in ("sh", "bash"):
                with self.subTest(shell=shell):
                    preview = subprocess.run([shell], input=installer.read_bytes(),
                                             cwd=home, env=env, capture_output=True)
                    self.assertEqual(preview.returncode, 0, preview.stderr)
                    self.assertEqual(preview.stdout, expected)
                    self.assertEqual(list(Path(home).iterdir()), [])

    def test_install_checks_pass(self):
        result = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        summary = re.search(r"^(\d+) passed, 0 failed$", result.stdout, re.MULTILINE)
        self.assertIsNotNone(summary, output)
        self.assertGreater(int(summary.group(1)), 0, output)


if __name__ == "__main__":
    unittest.main()
