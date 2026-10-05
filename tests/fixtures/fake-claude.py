#!/usr/bin/env python3
"""Offline Claude protocol fixture, configured only by the test's wrapper."""

import json
import os
import sys
import time
from pathlib import Path


def main(mode: str, counter: Path) -> None:
    flags = (
        "--print --output-format --verbose --tools --allowedTools "
        "--permission-mode --setting-sources --settings --strict-mcp-config "
        "--mcp-config --no-session-persistence --json-schema --system-prompt "
        "--model --max-budget-usd"
    )
    if "--help" in sys.argv:
        print(flags)
        return
    if "--version" in sys.argv:
        print("fake-claude 1.0")
        return

    arguments = sys.argv[1:]
    judge = "--json-schema" in arguments
    home = Path(os.environ["HOME"])
    config = Path(os.environ["CLAUDE_CONFIG_DIR"])
    work = Path.cwd()
    assert home.parent == work.parent
    assert config.is_relative_to(home)
    assert not os.environ.get("CODEX_HOME")
    assert not os.environ.get("ANTHROPIC_AUTH_TOKEN")
    assert not os.environ.get("CLAUDE_CODE_SIMPLE")
    assert not os.environ.get("EVAL_UNMANAGED_SECRET")
    assert "--bare" not in arguments
    assert "--dangerously-skip-permissions" not in arguments
    assert arguments[arguments.index("--permission-mode") + 1] == "dontAsk"
    assert arguments[arguments.index("--setting-sources") + 1] == "user"
    assert arguments[arguments.index("--tools") + 1] == ("" if judge else "Skill")
    settings = json.loads((config / "settings.json").read_text())
    assert settings["disableAllHooks"] is True
    if judge:
        assert not (config / "skills").exists()
        installed = []
    else:
        installed = sorted(p.name for p in (config / "skills").iterdir())
        assert "example-skill" in installed
        assert "other-skill" in installed
    prompt = sys.stdin.read()

    def emit(value: dict) -> None:
        print(json.dumps(value), flush=True)

    if mode == "timeout":
        time.sleep(2)
    if mode == "cancel":
        counter.write_text(str(os.getpid()))
        time.sleep(60)
    if mode == "malformed":
        print("not a JSON event")
        return
    if mode == "nonzero":
        print(os.environ["ANTHROPIC_API_KEY"], file=sys.stderr)
        sys.exit(1)

    emit({"type": "system", "subtype": "init", "model": "fake-model",
          "slash_commands": [] if mode == "undiscovered" else installed})
    if judge:
        data = json.loads(prompt)
        grades = []
        for index, assertion in enumerate(data["assertions"], start=1):
            grades.append({"index": index, "passed": "FAIL" not in data["response"],
                           "evidence": {"source": "response",
                                        "quote": data["response"],
                                        "reason": "Observed fixture response."}})
        if mode == "bad-judge":
            grades[0]["passed"] = "true"
        if mode == "invented-evidence":
            grades[0]["evidence"]["quote"] = "fabricated evidence"
        if mode == "duplicate-grade":
            grades.append(grades[0])
        emit({"type": "result", "subtype": "success", "is_error": False,
              "structured_output": {"assertions": grades}})
        return

    count = int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(count + 1))
    if mode != "no-load":
        emit({"type": "user" if mode == "spoofed-roles" else "assistant", "message": {"content": [
            {"type": "tool_use", "id": "skill-1", "name": "Skill",
             "input": {"skill": "example-skill"}}]}})
        if mode != "unconfirmed-load":
            emit({"type": "assistant" if mode == "spoofed-roles" else "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "skill-1",
                 "is_error": mode == "denied-load", "content": "Launching skill"}]}})
    if mode == "truncated":
        return
    if mode == "invalid-block":
        emit({"type": "assistant", "message": {"content": "invalid"}})
    response = "FAIL" if mode == "one-failure" and count % 5 == 4 else "PASS fixture response"
    if mode == "redact":
        response += " " + os.environ["ANTHROPIC_API_KEY"]
        print(os.environ["ANTHROPIC_API_KEY"], file=sys.stderr)
    result = {"type": "result", "subtype": "success", "is_error": False,
              "result": response, "total_cost_usd": 0.0, "permission_denials": []}
    if mode == "error-result":
        result.update(is_error=True, subtype="error_during_execution")
    if mode == "permission-denial":
        result["permission_denials"] = [{"tool_name": "Skill"}]
    emit(result)
