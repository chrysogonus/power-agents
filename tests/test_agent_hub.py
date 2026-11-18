#!/usr/bin/env python3
"""Tests for the agent hub hooks, run with fake notifiers on PATH."""

from __future__ import annotations

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "hooks" / "agent-hub.py"
RECORDER = '#!/bin/sh\nprintf "%s\\n" "$@" >"$NOTIFY_RECORD.tmp"\n' \
    '/bin/mv "$NOTIFY_RECORD.tmp" "$NOTIFY_RECORD"\n'


class NotifyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.record = self.directory / "record"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def add_notifier(self, name: str) -> None:
        path = self.bin / name
        path.write_text(RECORDER, encoding="utf-8")
        path.chmod(0o755)

    def notify(self, agent: str, payload: object) -> subprocess.CompletedProcess:
        stdin = payload if isinstance(payload, str) else json.dumps(payload)
        return subprocess.run(
            [sys.executable, str(HUB), "notify", "--agent", agent],
            input=stdin,
            capture_output=True,
            text=True,
            env={**os.environ, "PATH": str(self.bin),
                 "NOTIFY_RECORD": str(self.record)},
            timeout=30,
            check=False,
        )

    def recorded_arguments(self) -> list[str]:
        deadline = time.monotonic() + 10
        while not self.record.exists():
            if time.monotonic() > deadline:
                self.fail("the notifier was not run")
            time.sleep(0.05)
        return self.record.read_text(encoding="utf-8").splitlines()

    def assert_silent_success(self, result: subprocess.CompletedProcess) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_notify_send_shows_the_project_and_message(self) -> None:
        self.add_notifier("notify-send")
        result = self.notify("claude", {
            "hook_event_name": "Notification",
            "cwd": "/work/shop",
            "message": "Claude needs your permission to use Bash",
        })
        self.assert_silent_success(result)
        self.assertEqual(self.recorded_arguments(), [
            "--", "Claude Code",
            "shop: Claude needs your permission to use Bash",
        ])

    def test_stop_and_permission_requests_have_fixed_messages(self) -> None:
        self.add_notifier("notify-send")
        self.assert_silent_success(self.notify(
            "codex", {"hook_event_name": "Stop", "cwd": "/work/shop"}))
        self.assertEqual(self.recorded_arguments()[1:], ["Codex", "shop: Finished"])

        self.record.unlink()
        self.assert_silent_success(self.notify("codex", {
            "hook_event_name": "PermissionRequest",
            "cwd": "/work/shop",
            "tool_name": "Bash",
        }))
        self.assertEqual(
            self.recorded_arguments()[1:], ["Codex", "shop: Needs approval: Bash"])

    def test_windows_toast_is_preferred_and_escapes_text(self) -> None:
        self.add_notifier("notify-send")
        self.add_notifier("powershell.exe")
        result = self.notify("claude", {
            "hook_event_name": "Notification",
            "cwd": "/work/o'shop",
            "message": "<b>&</b>",
        })
        self.assert_silent_success(result)

        arguments = self.recorded_arguments()
        self.assertEqual(arguments[:3], ["-NoProfile", "-NonInteractive",
                                         "-EncodedCommand"])
        script = base64.b64decode(arguments[3]).decode("utf-16-le")
        self.assertIn("<text>Claude Code</text>", script)
        self.assertIn("<text>o''shop: &lt;b&gt;&amp;&lt;/b&gt;</text>", script)
        self.assertNotIn("<b>", script)

    def test_curly_quotes_cannot_end_the_powershell_string(self) -> None:
        self.add_notifier("powershell.exe")
        self.assert_silent_success(self.notify("claude", {
            "hook_event_name": "Notification",
            "cwd": "/work/it\u2019s",
            "message": "\u2018a\u2019 \u201ab\u201b'); calc; ('",
        }))

        arguments = self.recorded_arguments()
        script = base64.b64decode(arguments[3]).decode("utf-16-le")
        for quote in "\u2018\u2019\u201a\u201b":
            self.assertNotIn(quote, script)
        self.assertIn("<text>it&#8217;s: &#8216;a&#8217; &#8218;b&#8219;''); calc; (''"
                      "</text>", script)

    def test_without_a_notifier_or_valid_input_it_still_succeeds(self) -> None:
        self.assert_silent_success(self.notify("claude", "not json"))
        self.assert_silent_success(self.notify("codex", ["a list"]))
        self.assertFalse(self.record.exists())


class ContextTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.home = self.directory / "home"
        self.repo = self.directory / "shop"
        self.home.mkdir()
        self.repo.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def git(self, *args: str) -> None:
        subprocess.run(["git", "-C", str(self.repo), *args], check=True,
                       capture_output=True)

    def context(self, cwd: Path | None = None) -> str:
        cwd = cwd or self.repo
        result = subprocess.run(
            [sys.executable, str(HUB), "context", "--agent", "claude"],
            input=json.dumps({"hook_event_name": "SessionStart",
                              "source": "startup", "cwd": str(cwd)}),
            capture_output=True,
            text=True,
            cwd=cwd,
            env={**os.environ, "HOME": str(self.home)},
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def add_handoff(self, name: str, text: str, age_hours: float) -> Path:
        path = self.home / ".agents" / "handoffs" / "shop" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        stamp = time.time() - age_hours * 3600
        os.utime(path, (stamp, stamp))
        return path

    def test_nothing_to_report_prints_nothing(self) -> None:
        self.assertEqual(self.context(), "")

    def test_git_branch_and_changes_are_reported(self) -> None:
        self.git("init", "-b", "main")
        (self.repo / "app.py").write_text("print()\n", encoding="utf-8")
        output = self.context()
        self.assertIn("Branch: No commits yet on main", output)
        self.assertIn("?? app.py", output)

    def test_long_git_status_is_capped(self) -> None:
        self.git("init", "-b", "main")
        for index in range(40):
            (self.repo / f"file{index:02}.txt").write_text("x", encoding="utf-8")
        output = self.context()
        self.assertIn("?? file00.txt", output)
        self.assertNotIn("file39.txt", output)
        self.assertIn("... and 25 more", output)

    def test_repository_fsmonitor_is_not_run(self) -> None:
        self.git("init", "-b", "main")
        marker = self.directory / "fsmonitor-ran"
        hook = self.directory / "fsmonitor.sh"
        hook.write_text(f"#!/bin/sh\ntouch '{marker}'\n", encoding="utf-8")
        hook.chmod(0o755)
        self.git("config", "core.fsmonitor", str(hook))
        self.context()
        self.assertFalse(marker.exists())

    def test_handoffs_are_listed_newest_first_with_their_first_line(self) -> None:
        old = self.add_handoff("2026-11-14T0900.md", "# Old plan\nmore", 50)
        new = self.add_handoff("2026-11-16T0900.md", "\n# Finish phase 3\n", 2)
        consumed = self.home / ".agents/handoffs/shop/done/2026-11-01.md"
        consumed.parent.mkdir()
        consumed.write_text("# Done\n", encoding="utf-8")
        for index in range(6):
            self.add_handoff(f"2026-10-0{index}.md", "# Older\n", 100 + index)

        output = self.context()
        self.assertLess(output.index(str(new)), output.index(str(old)))
        self.assertIn(f"{new} (2 h old): Finish phase 3", output)
        self.assertIn(f"{old} (2 d old): Old plan", output)
        self.assertNotIn("Done", output)
        self.assertEqual(output.count("Older"), 3)
        self.assertIn("... and 3 older", output)

    def test_memory_index_is_included_and_capped(self) -> None:
        index = self.home / ".agents" / "memory" / "MEMORY.md"
        index.parent.mkdir(parents=True)
        index.write_text("".join(f"- [Fact {n}](fact-{n}.md) — hook\n"
                                 for n in range(200)), encoding="utf-8")
        output = self.context()
        self.assertIn(str(index), output)
        self.assertIn("- [Fact 0](fact-0.md)", output)
        self.assertIn("- [Fact 149](fact-149.md)", output)
        self.assertNotIn("Fact 150]", output)
        self.assertIn("truncated", output)

        index.write_text("x" * 20000, encoding="utf-8")
        self.assertLess(len(self.context()), 9000)

    def test_invalid_input_falls_back_to_the_working_directory(self) -> None:
        self.git("init", "-b", "main")
        result = subprocess.run(
            [sys.executable, str(HUB), "context", "--agent", "codex"],
            input="not json", capture_output=True, text=True, cwd=self.repo,
            env={**os.environ, "HOME": str(self.home)}, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Branch: No commits yet on main", result.stdout)


class CoordinationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.home = self.directory / "home"
        self.home.mkdir()
        self.repo = self.make_repo("shop")
        self.portfolio = self.home / ".agents" / "portfolio.json"
        self.locks = self.home / ".agents" / "locks"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def make_repo(self, name: str) -> Path:
        path = self.directory / name
        subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
        return path.resolve()

    def hub(self, command: str, session: str = "s1", agent: str = "claude",
            cwd: Path | None = None, source: str = "startup") -> str:
        cwd = cwd or self.repo
        result = subprocess.run(
            [sys.executable, str(HUB), command, "--agent", agent],
            input=json.dumps({"session_id": session, "cwd": str(cwd),
                              "source": source}),
            capture_output=True, text=True, cwd=cwd,
            env={**os.environ, "HOME": str(self.home)}, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def lock_files(self) -> list[Path]:
        return sorted(self.locks.glob("*/*.json"))

    def test_session_start_records_the_project_in_the_portfolio(self) -> None:
        self.portfolio.parent.mkdir(parents=True)
        self.portfolio.write_text(json.dumps({"projects": {
            "/elsewhere/kept": {"name": "kept", "path": "/elsewhere/kept"}}}),
            encoding="utf-8")
        self.hub("context", agent="codex")
        projects = json.loads(self.portfolio.read_text(encoding="utf-8"))["projects"]
        self.assertIn("/elsewhere/kept", projects)
        entry = projects[str(self.repo)]
        self.assertEqual((entry["name"], entry["path"], entry["branch"],
                          entry["last_agent"]),
                         ("shop", str(self.repo), "main", "codex"))
        self.assertRegex(entry["last_seen"], r"^\d{4}-\d{2}-\d{2}T")

        plain = self.directory / "notes"
        plain.mkdir()
        self.hub("context", cwd=plain)
        projects = json.loads(self.portfolio.read_text(encoding="utf-8"))["projects"]
        self.assertNotIn(str(plain), projects)

    def test_an_unreadable_portfolio_is_left_alone(self) -> None:
        self.portfolio.parent.mkdir(parents=True)
        self.portfolio.write_text("{broken", encoding="utf-8")
        self.hub("context")
        self.assertEqual(self.portfolio.read_text(encoding="utf-8"), "{broken")

    def test_a_second_session_is_warned_about_the_first(self) -> None:
        self.assertNotIn("Another", self.hub("context", session="s1"))
        self.assertEqual(len(self.lock_files()), 1)

        output = self.hub("context", session="s2", agent="codex")
        self.assertIn("Another claude session", output)
        self.assertIn("using-git-worktrees", output)
        self.assertEqual(len(self.lock_files()), 2)
        # A session that restarts is warned only about the other one.
        output = self.hub("context", session="s1", source="clear")
        self.assertIn("Another codex session", output)
        self.assertNotIn("Another claude session", output)

    def test_stale_and_ended_sessions_do_not_warn(self) -> None:
        self.hub("context", session="s1")
        stale = time.time() - 31 * 60
        os.utime(self.lock_files()[0], (stale, stale))
        self.assertNotIn("Another", self.hub("context", session="s2"))
        self.assertEqual([path.stem for path in self.lock_files()], ["s2"])

        self.hub("end", session="s2")
        self.assertEqual(self.lock_files(), [])
        self.assertNotIn("Another", self.hub("context", session="s3"))

    def test_the_portfolio_report_does_not_remove_stale_locks(self) -> None:
        self.hub("context", session="s1")
        stale = time.time() - 31 * 60
        os.utime(self.lock_files()[0], (stale, stale))

        report = self.hub("portfolio")

        self.assertIn("| shop | main | 0 | - |", report)
        self.assertEqual([path.stem for path in self.lock_files()], ["s1"])

    def test_activity_refreshes_the_lock(self) -> None:
        self.hub("context", session="s1")
        old = time.time() - 20 * 60
        os.utime(self.lock_files()[0], (old, old))
        self.hub("activity", session="s1")
        self.assertGreater(self.lock_files()[0].stat().st_mtime, old + 60)

    def test_resume_takes_the_lock_without_printing_context(self) -> None:
        self.assertEqual(self.hub("context", session="s1", source="resume"), "")
        self.assertEqual(len(self.lock_files()), 1)

    def test_worktrees_have_their_own_lock(self) -> None:
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=t",
                        "-c", "user.email=t@t", "commit", "-q",
                        "--allow-empty", "-m", "init"], check=True)
        worktree = self.directory / "shop-feature"
        subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "-q",
                        "-b", "feature", str(worktree)], check=True)
        self.hub("context", session="s1")
        self.assertNotIn("Another", self.hub("context", session="s2",
                                             cwd=worktree))

    def test_handoff_inbox_and_portfolio_pointer(self) -> None:
        self.hub("context")
        self.assertTrue((self.home / ".agents" / "handoffs").is_dir())
        other = self.make_repo("api")
        output = self.hub("context", cwd=other, session="s9")
        self.assertIn("1 other project", output)
        self.assertIn("portfolio", output)

    def test_portfolio_report_lists_projects_sessions_and_handoffs(self) -> None:
        self.hub("context", session="s1")
        api = self.make_repo("api")
        (api / "new.txt").write_text("x", encoding="utf-8")
        self.hub("context", session="s2", cwd=api, agent="codex")
        inbox = self.home / ".agents" / "handoffs" / "api"
        inbox.mkdir(parents=True)
        (inbox / "2026-11-16T120000Z.md").write_text("# Next\n", encoding="utf-8")
        gone = self.make_repo("gone")
        self.hub("context", session="s3", cwd=gone)
        shutil.rmtree(gone)

        report = self.hub("portfolio")
        self.assertIn("| shop | main | 0 |", report)
        self.assertIn("| api | main | 1 |", report)
        api_row = next(line for line in report.splitlines() if "| api |" in line)
        self.assertIn("codex", api_row)
        self.assertIn("| 1 |", api_row)
        self.assertIn("gone", report)
        self.assertIn("missing", report)


# Records its working directory and arguments, and upper-cases each file.
FORMATTER = """#!/bin/sh
pwd >"$FORMAT_RECORD"
for file in "$@"; do
  printf '%s\\n' "$file" >>"$FORMAT_RECORD"
  [ -f "$file" ] || continue
  upper=$(tr a-z A-Z <"$file") && printf '%s\\n' "$upper" >"$file"
done
"""


class FormatTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name).resolve()
        self.home = self.directory / "home"
        self.home.mkdir()
        self.repo = self.directory / "shop"
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.formatter = self.directory / "fmt"
        self.formatter.write_text(FORMATTER, encoding="utf-8")
        self.formatter.chmod(0o755)
        self.record = self.directory / "record"
        self.write_projects({"~/../shop": {"format": f"'{self.formatter}' --quiet"}})

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_projects(self, projects: object) -> None:
        path = self.home / ".config" / "power-agents" / "projects.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(projects), encoding="utf-8")

    def write(self, name: str, text: str = "hello\n") -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def format(self, payload: dict, agent: str = "claude") -> str:
        result = subprocess.run(
            [sys.executable, str(HUB), "format", "--agent", agent],
            input=json.dumps({"hook_event_name": "PostToolUse",
                              "cwd": str(self.repo), **payload}),
            capture_output=True, text=True, cwd=self.repo,
            env={**os.environ, "HOME": str(self.home),
                 "FORMAT_RECORD": str(self.record)},
            timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def edit(self, path: Path, tool: str = "Edit") -> str:
        return self.format({"tool_name": tool, "tool_input": {"file_path": str(path)}})

    def context(self, output: str) -> str:
        hook = json.loads(output)["hookSpecificOutput"]
        self.assertEqual(hook["hookEventName"], "PostToolUse")
        return hook["additionalContext"]

    def recorded(self) -> list[str]:
        return self.record.read_text(encoding="utf-8").splitlines()

    def test_edit_runs_the_project_formatter_and_reports_the_change(self) -> None:
        path = self.write("src/my app.py")
        message = self.context(self.edit(path))
        self.assertEqual(self.recorded(), [str(self.repo), "--quiet", str(path)])
        self.assertEqual(path.read_text(encoding="utf-8"), "HELLO\n")
        self.assertIn("src/my app.py", message)
        self.assertIn("Read it again", message)

    def test_an_already_formatted_file_prints_nothing(self) -> None:
        path = self.write("a.py", "HELLO\n")
        self.assertEqual(self.edit(path, tool="Write"), "")
        self.assertEqual(self.recorded()[-1], str(path))

    def test_apply_patch_formats_the_files_it_added_updated_or_moved(self) -> None:
        added = self.write("added.py")
        updated = self.write("updated.py")
        moved = self.write("new/moved.py")
        patch = "\n".join([
            "*** Begin Patch", "*** Add File: added.py", "+hello",
            "*** Update File: updated.py", "@@", "-x", "+hello",
            "*** Update File: old.py", "*** Move to: new/moved.py", "@@", "+hello",
            "*** Delete File: deleted.py", "*** End Patch"])
        message = self.context(self.format(
            {"tool_name": "apply_patch", "tool_input": {"command": patch}}, agent="codex"))
        self.assertEqual(self.recorded(),
                         [str(self.repo), "--quiet", str(added), str(updated), str(moved)])
        self.assertIn("new/moved.py", message)
        self.assertIn("Read them again", message)

    def test_other_tools_and_projects_without_a_formatter_run_nothing(self) -> None:
        path = self.write("a.py")
        self.assertEqual(self.format({"tool_name": "Bash",
                                      "tool_input": {"command": "true"}}), "")
        self.write_projects({str(self.repo): {"check": "true"}})
        self.assertEqual(self.edit(path), "")
        self.write_projects({str(self.repo): {"format": 1}})
        self.assertEqual(self.edit(path), "")
        self.assertFalse(self.record.exists())

    def test_a_blank_formatter_command_runs_nothing(self) -> None:
        script = self.write("build.sh", f"#!/bin/sh\ntouch '{self.record}'\n")
        script.chmod(0o755)
        for command in ("", "  "):
            self.write_projects({str(self.repo): {"format": command}})
            self.assertEqual(self.edit(script), "")
        self.assertFalse(self.record.exists(), "the edited file was run")

    def test_files_outside_the_repository_are_not_formatted(self) -> None:
        outside = self.directory / "outside.py"
        outside.write_text("hello\n", encoding="utf-8")
        (self.repo / "link.py").symlink_to(outside)
        self.assertEqual(self.edit(outside), "")
        self.assertEqual(self.edit(self.repo / "link.py"), "")
        self.assertEqual(self.edit(self.repo / "missing.py"), "")
        self.assertFalse(self.record.exists())
        self.assertEqual(outside.read_text(encoding="utf-8"), "hello\n")

    def test_a_failing_formatter_is_reported_with_its_output(self) -> None:
        self.write_projects({str(self.repo): {"format": "echo 'syntax error'; exit 3"}})
        message = self.context(self.edit(self.write("a.py")))
        self.assertIn("exit code 3", message)
        self.assertIn("syntax error", message)


class FocusTests(unittest.TestCase):
    """A toast click brings the session's window, and its Windows Terminal
    tab, forward through a Windows link handler, on WSL."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.home = self.directory / "home"
        self.home.mkdir()
        self.windows = self.home / ".agents" / "windows"
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.record = self.directory / "record"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def add_powershell(self, script: str = RECORDER) -> None:
        path = self.bin / "powershell.exe"
        path.write_text(script, encoding="utf-8")
        path.chmod(0o755)

    def hub(self, *arguments: str, payload: object = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(HUB), *arguments],
            input=json.dumps(payload) if payload is not None else "",
            capture_output=True, text=True, timeout=30, check=False,
            env={**os.environ, "PATH": str(self.bin), "HOME": str(self.home),
                 "NOTIFY_RECORD": str(self.record)},
        )

    def powershell_script(self) -> str:
        deadline = time.monotonic() + 10
        while not self.record.exists():
            if time.monotonic() > deadline:
                self.fail("powershell.exe was not run")
            time.sleep(0.05)
        arguments = self.record.read_text(encoding="utf-8").splitlines()
        self.assertEqual(arguments[-2], "-EncodedCommand")
        return base64.b64decode(arguments[-1]).decode("utf-16-le")

    def toast(self, session: str) -> str:
        result = self.hub("notify", "--agent", "codex", payload={
            "hook_event_name": "Stop", "cwd": "/work/shop", "session_id": session})
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        return self.powershell_script()

    def test_each_prompt_records_the_foreground_window(self) -> None:
        self.add_powershell('#!/bin/sh\nprintf "591120\\r\\n"\n')
        stale = self.windows / "old-session"
        stale.parent.mkdir(parents=True)
        stale.write_text("1\n", encoding="utf-8")
        week_ago = time.time() - 8 * 24 * 3600
        os.utime(stale, (week_ago, week_ago))

        result = self.hub("window", "--agent", "claude", payload={"session_id": "s1"})

        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        deadline = time.monotonic() + 10
        record = self.windows / "s1"
        while not (record.exists() and record.read_text(encoding="utf-8").strip()):
            if time.monotonic() > deadline:
                self.fail("the window was not recorded")
            time.sleep(0.05)
        self.assertEqual(record.read_text(encoding="utf-8").strip(), "591120")
        self.assertFalse(stale.exists(), "an old window record was kept")

    def test_a_prompt_in_windows_terminal_records_its_tab(self) -> None:
        self.add_powershell(RECORDER + 'printf "591120/42.330320.4.44\\r\\n"\n')

        self.hub("window", "--agent", "codex", payload={"session_id": "s1"})

        script = self.powershell_script()
        self.assertIn("CASCADIA_HOSTING_WINDOW_CLASS", script)
        self.assertIn("IsSelected", script)
        record = self.windows / "s1"
        deadline = time.monotonic() + 10
        while not (record.exists() and record.read_text(encoding="utf-8").strip()):
            if time.monotonic() > deadline:
                self.fail("the window was not recorded")
            time.sleep(0.05)
        self.assertEqual(record.read_text(encoding="utf-8").strip(),
                         "591120/42.330320.4.44")

    def test_a_failed_recording_keeps_the_last_record(self) -> None:
        self.add_powershell(RECORDER + "exit 1\n")
        self.windows.mkdir(parents=True)
        record = self.windows / "s1"
        record.write_text("591120\r\n", encoding="utf-8")

        self.hub("window", "--agent", "claude", payload={"session_id": "s1"})
        self.powershell_script()
        time.sleep(0.5)

        self.assertEqual(record.read_bytes(), b"591120\r\n")
        self.assertEqual([path.name for path in self.windows.iterdir()], ["s1"])

    def test_without_powershell_or_a_session_nothing_is_recorded(self) -> None:
        for payload in ({"session_id": "s1"}, {}):
            result = self.hub("window", "--agent", "codex", payload=payload)
            self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        self.add_powershell('#!/bin/sh\necho 591120\n')
        self.hub("window", "--agent", "codex", payload={})
        time.sleep(0.5)
        self.assertFalse(self.windows.exists() and any(self.windows.iterdir()))

    def test_a_toast_for_a_recorded_session_opens_its_window(self) -> None:
        self.add_powershell()
        self.windows.mkdir(parents=True)
        (self.windows / "s1").write_text("591120\r\n", encoding="utf-8")

        self.assertIn('<toast activationType="protocol" '
                      'launch="power-agents-focus:591120">', self.toast("s1"))

    def test_a_toast_for_a_recorded_tab_opens_that_tab(self) -> None:
        self.add_powershell()
        self.windows.mkdir(parents=True)
        (self.windows / "s1").write_text("591120/42.330320.4.44\r\n", encoding="utf-8")

        self.assertIn('<toast activationType="protocol" '
                      'launch="power-agents-focus:591120/42.330320.4.44">',
                      self.toast("s1"))

    def test_a_toast_without_a_valid_record_is_not_clickable(self) -> None:
        self.add_powershell()
        self.windows.mkdir(parents=True)
        records = ("12'; calc\n", "591120/42\n", "591120/42.x\n", "591120/\n",
                   "591120/1.2/3.4\n")
        for index, text in enumerate(records):
            (self.windows / f"s{index}").write_text(text, encoding="utf-8")

        for session in [f"s{index}" for index in range(len(records))] + ["missing"]:
            self.record.unlink(missing_ok=True)
            script = self.toast(session)
            self.assertIn("<toast>", script, session)
            self.assertNotIn("launch=", script, session)

    def test_installing_the_handler_registers_the_link_and_its_program(self) -> None:
        self.add_powershell()
        result = self.hub("focus-handler", "install")
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.powershell_script()
        self.assertIn(r"HKCU:\Software\Classes\power-agents-focus", script)
        # A Windows program opens no console window, unlike powershell.exe.
        self.assertIn("-OutputType WindowsApplication", script)
        self.assertIn("-ReferencedAssemblies UIAutomationClient, UIAutomationTypes",
                      script)
        self.assertIn("""'"{0}" "%1"' -f $program""", script)
        self.assertNotIn("powershell.exe", script)
        encoded = script.split("FromBase64String('")[1].split("'")[0]
        handler = base64.b64decode(encoded).decode("utf-8")
        self.assertIn(r'@"^power-agents-focus:([0-9]{1,10})'
                      r'(?:/([0-9]{1,10}(?:\.[0-9]{1,10}){1,7}))?/?\z"', handler)
        self.assertIn("IsWindow", handler)
        self.assertIn("SetForegroundWindow", handler)
        self.assertIn("SelectionItemPattern", handler)

    def test_removing_the_handler_deletes_the_link_and_its_program(self) -> None:
        self.add_powershell()
        result = self.hub("focus-handler", "remove")
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.powershell_script()
        self.assertIn(r"Remove-Item -LiteralPath 'HKCU:\Software\Classes\power-agents-focus'",
                      script)
        self.assertIn("focus-window.exe", script)
        self.assertIn("focus-window.ps1", script)  # left by earlier installs

    def test_a_failed_handler_change_exits_nonzero(self) -> None:
        self.add_powershell("#!/bin/sh\nexit 3\n")
        self.assertNotEqual(self.hub("focus-handler", "install").returncode, 0)
        self.bin.joinpath("powershell.exe").unlink()
        self.assertNotEqual(self.hub("focus-handler", "remove").returncode, 0)


if __name__ == "__main__":
    unittest.main()
