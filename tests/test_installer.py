"""Regression tests for the installer; safe to run on any Linux host."""
import json
from pathlib import Path
import re
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "MOzcelik-Debian-FSKS.sh"
SOURCE = SCRIPT.read_text(encoding="utf-8")


class InstallerTests(unittest.TestCase):
    def test_apt_source_updates_preserve_other_repositories(self):
        match = re.search(
            r"    awk '\n(.*?)\n    ' \"\$file\" > \"\$tmp\"",
            SOURCE,
            re.S,
        )
        self.assertIsNotNone(match, "Could not find APT source updater")
        source = (
            "deb http://deb.debian.org/debian trixie main # keep this comment\n"
            "deb [signed-by=/some/key.gpg] http://deb.debian.org/debian trixie main\n"
            "deb http://deb.debian.org/debian bookworm main\n"
            "deb https://third-party.example/repo trixie main\n"
            "# deb http://deb.debian.org/debian trixie main\n"
            "Components: main\n"
        )

        def update(data):
            done = subprocess.run(
                ["awk", match.group(1)],
                input=data,
                text=True,
                capture_output=True,
                check=True,
            )
            return done.stdout

        updated = update(source)
        self.assertIn(
            "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware # keep this comment",
            updated,
        )
        self.assertIn(
            "deb [signed-by=/some/key.gpg] http://deb.debian.org/debian trixie main contrib non-free non-free-firmware",
            updated,
        )
        self.assertIn("deb https://third-party.example/repo trixie main\n", updated)
        self.assertIn("deb http://deb.debian.org/debian bookworm main\n", updated)
        self.assertIn("# deb http://deb.debian.org/debian trixie main\n", updated)
        self.assertIn("Components: main contrib non-free non-free-firmware\n", updated)
        self.assertEqual(updated, update(updated), "APT source edits must be idempotent")

    def test_fastfetch_json(self):
        match = re.search(
            r'cat > "\$HOME/\.config/fastfetch/config\.jsonc" <<\x27EOF\x27\n(.*?)\nEOF',
            SOURCE,
            re.S,
        )
        self.assertIsNotNone(match)
        data = json.loads(match.group(1))
        self.assertEqual(data["logo"]["source"], "debian")
        self.assertIn("modules", data)

    def test_no_unsafe_automatic_kernel_or_prefix(self):
        self.assertIn('if [[ "$FSKS_BACKPORTS_KERNEL" == "1" ]]', SOURCE)
        self.assertIn('if [[ "$FSKS_WINETRICKS" == "1" ]]', SOURCE)
        self.assertIn('if [[ "$FSKS_PURGE_APPS" == "1" ]]', SOURCE)
        self.assertIn('if [[ "$FSKS_GRUB_TUNING" == "1" ]]', SOURCE)
        self.assertNotIn("dxvk2030", SOURCE)
        self.assertNotIn("starship.rs/install.sh", SOURCE)
        self.assertNotIn("GRUB_TIMEOUT=0", SOURCE)


if __name__ == "__main__":
    unittest.main()
