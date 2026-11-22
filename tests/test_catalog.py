import csv
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CatalogTests(unittest.TestCase):
    def test_availability_and_installer_support(self):
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        env = dict(os.environ, COLD_HOME=f"{fixture.name}/tools", COLD_BIN=f"{fixture.name}/bin")
        listing = subprocess.check_output([ROOT / "cold", "list"], text=True)
        rows = list(csv.DictReader(listing.splitlines(), delimiter="\t"))
        self.assertEqual(
            [(row["tool"], row["availability"], row["cold_install"]) for row in rows],
            [
                ("coldbox", "public source", "yes"),
                ("coldcleaner", "public source", "yes"),
                ("coldlocker", "public source", "yes"),
                ("coldfix", "public source", "yes"),
                ("coldvault", "public source", "yes"),
                ("coldpass", "web only", "no"),
                ("coldrelease", "public source", "yes"),
                ("coldverify", "public source", "yes"),
                ("coldguardian", "public source", "yes"),
                ("coldrewind", "public source", "yes"),
                ("coldcontribute", "parked", "no"),
            ],
        )
        for row in rows:
            with self.subTest(tool=row["tool"]):
                preview = subprocess.run(
                    [ROOT / "cold", "install", row["tool"]], capture_output=True, text=True, env=env
                )
                if row["cold_install"] == "yes":
                    self.assertEqual(preview.returncode, 0, preview.stderr)
                    self.assertIn(f'+ git clone {row["url"]}.git ', preview.stdout)
                else:
                    self.assertEqual(preview.returncode, 2, preview.stdout)
                    self.assertNotIn("git clone", preview.stdout)
        self.assertEqual(list(Path(fixture.name).iterdir()), [])

    def test_discovery_files_are_current(self):
        listing = subprocess.check_output([ROOT / "cold", "list"], text=True)
        rows = list(csv.DictReader(listing.splitlines(), delimiter="\t"))
        tools = json.loads((ROOT / "tools.json").read_text())["tools"]
        self.assertEqual(
            [(tool["id"], tool["availability"], tool["cold_install"], tool["url"]) for tool in tools],
            [(row["tool"], row["availability"], row["cold_install"] == "yes", row["url"] or None)
             for row in rows],
        )
        subprocess.run(["python3", ROOT / "render_catalog.py", "--check"], check=True)
