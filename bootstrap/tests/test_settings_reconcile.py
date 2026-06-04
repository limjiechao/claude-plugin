import json
import tempfile
import unittest
from pathlib import Path

from bootstrap.settings_reconcile import reconcile_settings_file


class SettingsReconcileTests(unittest.TestCase):
    def test_removes_managed_scalar_when_deleted_from_snippet(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            snippet = root / "snippet.json"
            last = root / "last.json"

            settings.write_text(json.dumps({"skipAutoPermissionPrompt": True, "userKey": "keep"}))
            snippet.write_text(json.dumps({"inputNeededNotifEnabled": True}))
            last.write_text(json.dumps({"skipAutoPermissionPrompt": True}))

            reconcile_settings_file(
                settings_path=settings,
                snippet_path=snippet,
                last_snippet_path=last,
                claude_dir="/tmp/claude",
                hooks_dir="/tmp/claude/hooks",
            )

            merged = json.loads(settings.read_text())
            self.assertNotIn("skipAutoPermissionPrompt", merged)
            self.assertEqual(merged["userKey"], "keep")
            self.assertEqual(merged["inputNeededNotifEnabled"], True)

    def test_preserves_user_modified_scalar_when_managed_key_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            snippet = root / "snippet.json"
            last = root / "last.json"

            settings.write_text(json.dumps({"skipAutoPermissionPrompt": False}))
            snippet.write_text(json.dumps({}))
            last.write_text(json.dumps({"skipAutoPermissionPrompt": True}))

            reconcile_settings_file(
                settings_path=settings,
                snippet_path=snippet,
                last_snippet_path=last,
                claude_dir="/tmp/claude",
                hooks_dir="/tmp/claude/hooks",
            )

            merged = json.loads(settings.read_text())
            self.assertEqual(merged["skipAutoPermissionPrompt"], False)

    def test_removes_managed_object_when_deleted_from_snippet(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            snippet = root / "snippet.json"
            last = root / "last.json"

            old_hook = {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/tmp/claude/hooks/git-guard.sh"}]}]}
            settings.write_text(json.dumps({"hooks": old_hook, "userKey": "keep"}))
            snippet.write_text(json.dumps({}))
            last.write_text(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "@@HOOKS_DIR@@/git-guard.sh"}]}]}}))

            reconcile_settings_file(
                settings_path=settings,
                snippet_path=snippet,
                last_snippet_path=last,
                claude_dir="/tmp/claude",
                hooks_dir="/tmp/claude/hooks",
            )

            merged = json.loads(settings.read_text())
            self.assertNotIn("hooks", merged)
            self.assertEqual(merged["userKey"], "keep")

    def test_removes_stale_managed_list_entries_and_keeps_user_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            snippet = root / "snippet.json"
            last = root / "last.json"

            settings.write_text(json.dumps({"permissions": {"allow": ["Bash(old:*)", "Bash(user:*)"]}}))
            snippet.write_text(json.dumps({"permissions": {"allow": ["Bash(new:*)"]}}))
            last.write_text(json.dumps({"permissions": {"allow": ["Bash(old:*)"]}}))

            reconcile_settings_file(
                settings_path=settings,
                snippet_path=snippet,
                last_snippet_path=last,
                claude_dir="/tmp/claude",
                hooks_dir="/tmp/claude/hooks",
            )

            merged = json.loads(settings.read_text())
            self.assertEqual(merged["permissions"]["allow"], ["Bash(user:*)", "Bash(new:*)"])

    def test_replaces_tokens_and_forces_statusline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            snippet = root / "snippet.json"
            last = root / "last.json"

            snippet.write_text(json.dumps({"hooks": {"PreToolUse": [{"hooks": [{"command": "@@HOOKS_DIR@@/git-guard.sh"}]}]}}))

            reconcile_settings_file(
                settings_path=settings,
                snippet_path=snippet,
                last_snippet_path=last,
                claude_dir="/tmp/claude",
                hooks_dir="/tmp/claude/hooks",
            )

            merged = json.loads(settings.read_text())
            self.assertEqual(merged["hooks"]["PreToolUse"][0]["hooks"][0]["command"], "/tmp/claude/hooks/git-guard.sh")
            self.assertEqual(merged["statusLine"], {"type": "command", "command": "bash /tmp/claude/statusline.sh"})
            self.assertEqual(json.loads(last.read_text()), json.loads(snippet.read_text()))


if __name__ == "__main__":
    unittest.main()
