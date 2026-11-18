#!/usr/bin/env python3
"""Hooks for the optional Power Agents components, for Codex and Claude Code.

notify: shows a desktop notification when the agent finishes a turn or waits
for approval, and prints nothing.

window: for a UserPromptSubmit hook on WSL, records the window in front (the
session's terminal, where the prompt was just typed), so that clicking the
session's Windows toast brings that window forward through the link handler
that "focus-handler install" registers for the installer.

context: for a SessionStart hook, records the repository in the portfolio and
takes a session lock, then prints session context: a warning about other active
sessions, the git branch and changes, waiting handoffs, a portfolio pointer,
and the cross-project memory index.

activity and end: refresh the session lock on each prompt and turn end, and
release it when the session ends.

portfolio: prints a table of every tracked project, for the portfolio skill.

format: for a PostToolUse hook on file edits, runs the repository's "format"
command from ~/.config/power-agents/projects.json on the edited files, and
tells the agent which files it changed or how it failed.

focus-handler install|remove: for the installer, registers or removes that
link handler, and exits 1 when PowerShell fails.

The hooks read the hook's JSON payload on stdin and always exit 0, so that a
hook problem never interrupts the agent.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape


TITLES = {"claude": "Claude Code", "codex": "Codex"}
# Codex trims hook context to about 2,500 tokens, so all of it stays below.
MAX_CONTEXT = 9000
MAX_STATUS_LINES = 15
MAX_HANDOFFS = 5
MAX_MEMORY_LINES = 150
MAX_MEMORY_BYTES = 8000
GIT_TIMEOUT = 5
# A lock untouched this long belongs to a session that is idle or gone.
LOCK_STALE_SECONDS = 30 * 60
SAFE_SESSION = re.compile(r"[A-Za-z0-9_.-]{1,128}")
MAX_BODY = 200
FORMAT_TIMEOUT = 45
MAX_FORMAT_OUTPUT = 2000
FILE_TOOLS = ("Edit", "Write", "MultiEdit")
PATCH_TARGET = re.compile(r"^\*\*\* (?:Add File|Update File|Move to): (.+?)\s*$", re.M)
# Windows only shows toasts from registered apps; this is Windows PowerShell's.
POWERSHELL_APP_ID = (
    "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe"
)
TOAST_SCRIPT = """\
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast{launch}><visual><binding template="ToastGeneric"><text>{title}</text><text>{body}</text></binding></visual></toast>')
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{app_id}').Show($toast)
"""
# Prints the window in front, and for Windows Terminal "/" and the selected
# tab's UI Automation runtime ID, which stays the same while the tab is open.
WINDOW_SCRIPT = """\
Add-Type -Namespace PowerAgents -Name Foreground -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(System.IntPtr window, System.Text.StringBuilder name, int size);
'@
$window = [PowerAgents.Foreground]::GetForegroundWindow()
$record = [string][long]$window
$class = New-Object System.Text.StringBuilder 256
[void][PowerAgents.Foreground]::GetClassName($window, $class, 256)
if ($class.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS') {
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        $tabs = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
        foreach ($tab in [System.Windows.Automation.AutomationElement]::FromHandle($window).FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabs)) {
            if ($tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) {
                $record += '/' + ($tab.GetRuntimeId() -join '.')
                break
            }
        }
    } catch {}
}
$record
"""
WINDOW_RECORD = re.compile(r"\s*([1-9][0-9]{0,9}(?:/[0-9]{1,10}(?:\.[0-9]{1,10}){1,7})?)\s*")
WINDOW_RECORD_DAYS = 7
# Runs the command after RECORD and replaces RECORD with its output, if any.
RECORD_WRITER = """\
import os, subprocess, sys
record = sys.argv[1]
output = subprocess.run(sys.argv[2:], stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
if output.strip():
    with open(record + ".tmp", "wb") as temporary:
        temporary.write(output)
    os.replace(record + ".tmp", record)
"""
FOCUS_SCHEME = "power-agents-focus"
FOCUS_KEY = f"HKCU:\\Software\\Classes\\{FOCUS_SCHEME}"
# Run by Windows for a power-agents-focus: link, which any program or web page
# can open, so it accepts only a window number and an optional tab ID. It is
# compiled as a Windows program because powershell.exe would open a console
# window first.
FOCUS_HANDLER = r"""using System;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Automation;

static class FocusWindow {
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);

    static int Main(string[] arguments) {
        if (arguments.Length != 1) return 1;
        Match match = Regex.Match(arguments[0],
            @"^power-agents-focus:([0-9]{1,10})(?:/([0-9]{1,10}(?:\.[0-9]{1,10}){1,7}))?/?\z");
        if (!match.Success) return 1;
        IntPtr window = new IntPtr(long.Parse(match.Groups[1].Value));
        if (!IsWindow(window)) return 1;
        if (IsIconic(window)) ShowWindow(window, 9);
        bool inFront = SetForegroundWindow(window);
        if (match.Groups[2].Success) SelectTab(window, match.Groups[2].Value);
        return inFront ? 0 : 1;
    }

    // A tab closed since the prompt is not found, and the window stays as is.
    static void SelectTab(IntPtr window, string id) {
        try {
            Condition tabs = new PropertyCondition(
                AutomationElement.ControlTypeProperty, ControlType.TabItem);
            foreach (AutomationElement tab in
                     AutomationElement.FromHandle(window).FindAll(TreeScope.Descendants, tabs)) {
                if (string.Join(".", tab.GetRuntimeId()) == id) {
                    ((SelectionItemPattern)tab.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
                    return;
                }
            }
        } catch (ElementNotAvailableException) {
        } catch (InvalidOperationException) {
        }
    }
}
"""
FOCUS_INSTALL_SCRIPT = """\
$ErrorActionPreference = 'Stop'
$directory = Join-Path $env:LOCALAPPDATA 'power-agents'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$program = Join-Path $directory 'focus-window.exe'
$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{handler}'))
if (Test-Path -LiteralPath $program) {{ Remove-Item -LiteralPath $program -Force }}
Add-Type -TypeDefinition $source -ReferencedAssemblies UIAutomationClient, UIAutomationTypes -OutputAssembly $program -OutputType WindowsApplication
$script = Join-Path $directory 'focus-window.ps1'
if (Test-Path -LiteralPath $script) {{ Remove-Item -LiteralPath $script -Force }}
$key = '{key}'
New-Item -Path "$key\\shell\\open\\command" -Force | Out-Null
Set-Item -LiteralPath $key -Value 'URL:Power Agents focus'
New-ItemProperty -LiteralPath $key -Name 'URL Protocol' -Value '' -Force | Out-Null
Set-Item -LiteralPath "$key\\shell\\open\\command" -Value ('"{{0}}" "%1"' -f $program)
"""
FOCUS_REMOVE_SCRIPT = """\
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath '{key}') {{ Remove-Item -LiteralPath '{key}' -Recurse -Force }}
$directory = Join-Path $env:LOCALAPPDATA 'power-agents'
foreach ($name in 'focus-window.exe', 'focus-window.ps1') {{
    $path = Join-Path $directory $name
    if (Test-Path -LiteralPath $path) {{ Remove-Item -LiteralPath $path -Force }}
}}
if ((Test-Path -LiteralPath $directory) -and -not (Get-ChildItem -LiteralPath $directory)) {{ Remove-Item -LiteralPath $directory }}
"""


def read_payload() -> dict[str, Any]:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, UnicodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def notification_body(payload: dict[str, Any]) -> str:
    cwd = payload.get("cwd")
    project = Path(cwd if isinstance(cwd, str) and cwd else os.getcwd()).name
    event = payload.get("hook_event_name")
    if event == "Stop":
        message = "Finished"
    elif event == "PermissionRequest":
        tool = payload.get("tool_name")
        message = f"Needs approval: {tool}" if isinstance(tool, str) else "Needs approval"
    else:
        message = payload.get("message")
        if not isinstance(message, str) or not message:
            message = "Needs your attention"
    return f"{project}: {message}"[:MAX_BODY]


# PowerShell also ends a single-quoted string at these quotes, so they become
# XML character references, which the toast shows as the same characters.
CURLY_QUOTES = {ord(quote): f"&#{ord(quote)};" for quote in "\u2018\u2019\u201a\u201b"}


def toast_text(value: str) -> str:
    """Escape VALUE for the toast XML inside a single-quoted PowerShell string."""
    return escape(value).translate(CURLY_QUOTES).replace("'", "''")


def powershell_command(powershell: str, script: str) -> list[str]:
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    return [powershell, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]


def window_record(session: str) -> Path:
    return agents_home() / "windows" / session


def recorded_window(payload: dict[str, Any]) -> str | None:
    session = session_id(payload)
    if session is None:
        return None
    try:
        match = WINDOW_RECORD.fullmatch(window_record(session).read_text(encoding="ascii"))
    except (OSError, UnicodeError):
        return None
    return match.group(1) if match else None


def notifier_command(title: str, body: str, window: str | None = None) -> list[str] | None:
    """A Windows toast (WSL or Git Bash), then notify-send, else None. A toast
    with WINDOW brings that window forward when clicked."""
    powershell = shutil.which("powershell.exe")
    if powershell:
        launch = (f' activationType="protocol" launch="{FOCUS_SCHEME}:{window}"'
                  if window else "")
        return powershell_command(powershell, TOAST_SCRIPT.format(
            title=toast_text(title), body=toast_text(body), app_id=POWERSHELL_APP_ID,
            launch=launch))
    notify_send = shutil.which("notify-send")
    if notify_send:
        return [notify_send, "--", title, body]
    return None


def ring_bell() -> None:
    try:
        with open("/dev/tty", "w", encoding="utf-8") as terminal:
            terminal.write("\a")
    except OSError:
        pass


def notify(agent: str) -> None:
    payload = read_payload()
    command = notifier_command(TITLES[agent], notification_body(payload),
                               recorded_window(payload))
    if command is None:
        ring_bell()
        return
    # Detached so a slow PowerShell start does not hold up the agent.
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def record_window() -> None:
    """Record the window in front for this session, without waiting for
    PowerShell, and drop records of sessions idle for a week."""
    session = session_id(read_payload())
    powershell = shutil.which("powershell.exe")
    if session is None or powershell is None:
        return
    directory = agents_home() / "windows"
    directory.mkdir(parents=True, exist_ok=True)
    cutoff = time.time() - WINDOW_RECORD_DAYS * 24 * 3600
    for path in directory.iterdir():
        try:
            if path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            continue
    # The record is replaced only once PowerShell has printed a window, so a
    # failed run keeps the last one, and toasts meanwhile still link to it.
    subprocess.Popen(
        [sys.executable, "-c", RECORD_WRITER, str(window_record(session)),
         *powershell_command(powershell, WINDOW_SCRIPT)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True)


def focus_handler(action: str) -> int:
    """Install or remove the Windows link handler for clickable toasts."""
    powershell = shutil.which("powershell.exe")
    if powershell is None:
        print("agent-hub focus-handler: powershell.exe is not on PATH", file=sys.stderr)
        return 1
    if action == "install":
        handler = base64.b64encode(FOCUS_HANDLER.encode("utf-8")).decode("ascii")
        script = FOCUS_INSTALL_SCRIPT.format(handler=handler, key=FOCUS_KEY)
    else:
        script = FOCUS_REMOVE_SCRIPT.format(key=FOCUS_KEY)
    try:
        result = subprocess.run(powershell_command(powershell, script),
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=60, check=False)
    except subprocess.TimeoutExpired:
        print("agent-hub focus-handler: PowerShell timed out", file=sys.stderr)
        return 1
    if result.returncode != 0:
        print(f"agent-hub focus-handler: PowerShell failed: {result.stderr.strip()}",
              file=sys.stderr)
    return 1 if result.returncode else 0


def session_directory(payload: dict[str, Any]) -> Path:
    cwd = payload.get("cwd")
    return Path(cwd) if isinstance(cwd, str) and cwd else Path.cwd()


def git(directory: Path, *args: str) -> str | None:
    """Run git without optional locks or the repository's fsmonitor command."""
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "-c", "core.fsmonitor=false",
             "-C", str(directory), *args],
            capture_output=True, text=True, timeout=GIT_TIMEOUT, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def git_section(directory: Path) -> list[str]:
    status = git(directory, "status", "--porcelain=v1", "--branch")
    if not status:
        return []
    branch, *changes = status.splitlines()
    lines = [f"Branch: {branch[3:] if branch.startswith('## ') else branch}"]
    if changes:
        lines.append(f"Uncommitted changes ({len(changes)}):")
        lines += [f"  {change}" for change in changes[:MAX_STATUS_LINES]]
        if len(changes) > MAX_STATUS_LINES:
            lines.append(f"  ... and {len(changes) - MAX_STATUS_LINES} more")
    return lines


def agents_home() -> Path:
    return Path.home() / ".agents"


def repository_root(directory: Path) -> Path | None:
    top = git(directory, "rev-parse", "--show-toplevel")
    return Path(top.strip()) if top and top.strip() else None


def current_branch(root: Path) -> str:
    branch = git(root, "symbolic-ref", "--short", "-q", "HEAD")
    return branch.strip() if branch and branch.strip() else "detached"


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def update_portfolio(root: Path, agent: str) -> int | None:
    """Record ROOT and return the number of other projects, or None when the
    portfolio is unreadable and was left alone."""
    path = agents_home() / "portfolio.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(agents_home() / ".portfolio.lock", "w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            data = {"projects": {}}
        except (ValueError, UnicodeError):
            return None
        if not isinstance(data, dict) or not isinstance(data.get("projects"), dict):
            return None
        data["projects"][str(root)] = {
            "name": root.name, "path": str(root), "branch": current_branch(root),
            "last_seen": now_iso(), "last_agent": agent,
        }
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    return len(data["projects"]) - 1


def lock_directory(root: Path) -> Path:
    digest = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:16]
    return agents_home() / "locks" / digest


def session_id(payload: dict[str, Any]) -> str | None:
    session = payload.get("session_id")
    if not isinstance(session, str) or not session:
        return None
    if SAFE_SESSION.fullmatch(session) and session not in (".", ".."):
        return session
    return hashlib.sha256(session.encode("utf-8")).hexdigest()[:32]


def other_sessions(root: Path, own: str | None,
                   prune: bool = True) -> list[tuple[str, float]]:
    """The agent and idle seconds of other fresh sessions; PRUNE deletes
    stale locks."""
    now = time.time()
    sessions = []
    for path in sorted(lock_directory(root).glob("*.json")):
        if path.stem == own:
            continue
        try:
            idle = now - path.stat().st_mtime
            if idle > LOCK_STALE_SECONDS:
                if prune:
                    path.unlink()
                continue
            agent = json.loads(path.read_text(encoding="utf-8")).get("agent")
        except (OSError, ValueError, AttributeError):
            continue
        sessions.append((agent if isinstance(agent, str) else "agent", idle))
    return sessions


def take_lock(root: Path, agent: str, session: str) -> None:
    path = lock_directory(root) / f"{session}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        os.utime(path)
        return
    path.write_text(json.dumps({"path": str(root), "agent": agent,
                                "session": session, "started": now_iso()}) + "\n",
                    encoding="utf-8")


def idle_text(seconds: float) -> str:
    return "just now" if seconds < 60 else f"{round(seconds / 60)} min ago"


def age(seconds: float) -> str:
    if seconds < 3600:
        return f"{max(round(seconds / 60), 1)} min old"
    if seconds < 86400:
        return f"{round(seconds / 3600)} h old"
    return f"{round(seconds / 86400)} d old"


def first_line(path: Path) -> str:
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            for line in handle:
                text = line.strip().lstrip("#").strip()
                if text:
                    return text[:100]
    except OSError:
        pass
    return "(empty)"


def handoff_section(project: str) -> list[str]:
    directory = Path.home() / ".agents" / "handoffs" / project
    handoffs = []
    for path in directory.glob("*.md"):
        # Another session may consume a handoff while this one starts.
        try:
            if path.is_file():
                handoffs.append((path.stat().st_mtime, path))
        except OSError:
            continue
    if not handoffs:
        return []
    handoffs.sort(reverse=True)
    now = time.time()
    lines = ["Handoffs waiting for this project, newest first. Read one only if "
             "the user's task continues it, and then move it into the done/ "
             "folder next to it:"]
    for modified, path in handoffs[:MAX_HANDOFFS]:
        lines.append(f"- {path} ({age(now - modified)}): {first_line(path)}")
    if len(handoffs) > MAX_HANDOFFS:
        lines.append(f"- ... and {len(handoffs) - MAX_HANDOFFS} older")
    return lines


def memory_section(budget: int) -> list[str]:
    index = Path.home() / ".agents" / "memory" / "MEMORY.md"
    try:
        text = index.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    if not text.strip():
        return []
    header = (f"Cross-project memory index ({index}). Read a linked file in "
              "that directory when it bears on the task:")
    lines = text.splitlines()
    kept = "\n".join(lines[:MAX_MEMORY_LINES])
    limit = min(MAX_MEMORY_BYTES, budget - len(header) - 200)
    if limit <= 0:
        return [f"Cross-project memory index: {index} (too long to include)."]
    truncated = len(lines) > MAX_MEMORY_LINES or len(kept) > limit
    kept = kept[:limit].rstrip()
    result = [header, kept]
    if truncated:
        result.append(f"(Index truncated; read {index} for the rest.)")
    return result


def context(agent: str) -> None:
    payload = read_payload()
    directory = session_directory(payload)
    root = repository_root(directory)
    session = session_id(payload)
    (agents_home() / "handoffs").mkdir(parents=True, exist_ok=True)

    coordination = []
    if root is not None:
        for other_agent, idle in other_sessions(root, session):
            coordination.append(
                f"Another {other_agent} session in this repository was active "
                f"{idle_text(idle)}. Before changing files, tell the user and "
                "suggest a separate worktree (using-git-worktrees), so the "
                "sessions do not overwrite each other's work.")
        if session:
            take_lock(root, agent, session)
        others = update_portfolio(root, agent)
        if others is None:
            coordination.append(f"Note: {agents_home() / 'portfolio.json'} is not "
                                "valid JSON, so it was not updated; tell the user.")
        elif others:
            plural = "s" if others > 1 else ""
            coordination.append(
                f"Portfolio: {others} other project{plural} tracked in "
                f"{agents_home() / 'portfolio.json'}; use the portfolio skill "
                "for an overview across projects.")
    if payload.get("source") in ("resume", "fork"):
        return

    sections = [coordination, git_section(directory),
                handoff_section(root.name if root else directory.name)]
    used = sum(len(line) + 1 for section in sections for line in section)
    sections.append(memory_section(MAX_CONTEXT - used))
    sections = [section for section in sections if section]
    if sections:
        text = "\n\n".join("\n".join(section) for section in sections)
        print(f"Session context from Power Agents:\n\n{text}"[:MAX_CONTEXT])


def session_lock(agent: str, release: bool) -> None:
    """Refresh this session's lock, or remove it when RELEASE is true."""
    payload = read_payload()
    root = repository_root(session_directory(payload))
    session = session_id(payload)
    if root is None or session is None:
        return
    if release:
        (lock_directory(root) / f"{session}.json").unlink(missing_ok=True)
    else:
        take_lock(root, agent, session)


def table_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def portfolio_report() -> None:
    path = agents_home() / "portfolio.json"
    try:
        projects = json.loads(path.read_text(encoding="utf-8"))["projects"]
        entries = sorted(projects.values(),
                         key=lambda entry: entry.get("last_seen", ""), reverse=True)
    except FileNotFoundError:
        print(f"No projects tracked yet: {path} is created when a session starts "
              "in a git repository with the context component installed.")
        return
    except (ValueError, UnicodeError, KeyError, TypeError, AttributeError):
        print(f"{path} is not a valid portfolio; fix or delete it.")
        return

    print(f"Projects tracked in {path}, most recent first:\n")
    print("| Project | Branch | Changes | Active sessions | Handoffs | Last session | Path |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for entry in entries:
        root = Path(str(entry.get("path", "")))
        name = str(entry.get("name", root.name))
        if not root.is_dir():
            branch, changes, active = "(missing)", "-", "-"
        else:
            status = git(root, "status", "--porcelain=v1")
            branch = current_branch(root)
            changes = len(status.splitlines()) if status is not None else "?"
            sessions = other_sessions(root, None, prune=False)
            active = ", ".join(f"{agent} ({idle_text(idle)})"
                               for agent, idle in sessions) or "-"
        inbox = agents_home() / "handoffs" / name
        handoffs = len([item for item in inbox.glob("*.md") if item.is_file()])
        last = f"{entry.get('last_seen', '?')} {entry.get('last_agent', '')}".strip()
        print("| " + " | ".join(table_cell(value) for value in
                                (name, branch, changes, active, handoffs, last,
                                 root)) + " |")


def load_projects() -> dict[str, dict[str, Any]]:
    """Read projects.json with the verify gate's validation; raise ValueError."""
    path = Path(__file__).resolve().parent / "verify-gate.py"
    spec = importlib.util.spec_from_file_location("verify_gate", path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.load_projects()


def edited_files(payload: dict[str, Any]) -> list[Path]:
    """Return the files an Edit, Write, MultiEdit, or apply_patch call wrote."""
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return []
    if payload.get("tool_name") in FILE_TOOLS:
        names = [tool_input.get("file_path")]
    elif payload.get("tool_name") == "apply_patch":
        patch = tool_input.get("command")
        if isinstance(patch, list):
            patch = "\n".join(item for item in patch if isinstance(item, str))
        names = PATCH_TARGET.findall(patch) if isinstance(patch, str) else []
    else:
        return []
    base = session_directory(payload)
    return [base / name for name in names if isinstance(name, str) and name]


def run_formatter(command: str, root: Path, files: list[Path]) -> tuple[int | None, str]:
    """Run COMMAND with FILES appended; return (exit code or None on timeout, output)."""
    process = subprocess.Popen(
        f"{command} {' '.join(shlex.quote(str(path)) for path in files)}",
        shell=True, cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, errors="replace",
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=FORMAT_TIMEOUT)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        return None, output
    return process.returncode, output


def digest(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def format_files() -> None:
    files = edited_files(read_payload())
    if not files:
        return
    try:
        projects = load_projects()
    except ValueError:
        return  # the verify gate's doctor reports an invalid projects.json
    groups: dict[Path, list[Path]] = {}
    for path in files:
        real = path.resolve()
        root = repository_root(real.parent) if real.is_file() else None
        root = root.resolve() if root else None
        command = projects.get(str(root), {}).get("format")
        if (root and root in real.parents and real not in groups.get(root, [])
                and isinstance(command, str) and command.strip()):
            groups.setdefault(root, []).append(real)
    messages = []
    for root, paths in groups.items():
        before = [digest(path) for path in paths]
        code, output = run_formatter(projects[str(root)]["format"], root, paths)
        names = ", ".join(str(path.relative_to(root)) for path in paths)
        changed = [str(path.relative_to(root)) for path, old in zip(paths, before)
                   if digest(path) != old]
        if code != 0:
            result = (f"timed out after {FORMAT_TIMEOUT} seconds" if code is None
                      else f"failed with exit code {code}")
            messages.append(f"The project formatter {result} on {names} in {root}."
                            + (f" Output:\n{output[-MAX_FORMAT_OUTPUT:]}"
                               if output.strip() else ""))
        if changed:
            messages.append(f"The project formatter changed {', '.join(changed)} in "
                            f"{root}. Read them again before you edit them.")
    if messages:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse", "additionalContext": "\n".join(messages)}}))


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("notify", "window", "context", "activity", "end", "format"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--agent", choices=sorted(TITLES), required=True)
    subparsers.add_parser("portfolio").add_argument("--agent", choices=sorted(TITLES))
    subparsers.add_parser("focus-handler").add_argument(
        "action", choices=("install", "remove"))
    arguments = parser.parse_args()

    if arguments.command == "focus-handler":
        return focus_handler(arguments.action)
    try:
        if arguments.command == "notify":
            notify(arguments.agent)
        elif arguments.command == "window":
            record_window()
        elif arguments.command == "context":
            context(arguments.agent)
        elif arguments.command == "format":
            format_files()
        elif arguments.command in ("activity", "end"):
            session_lock(arguments.agent, release=arguments.command == "end")
        else:
            portfolio_report()
    except OSError as error:
        print(f"agent-hub {arguments.command}: {error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
