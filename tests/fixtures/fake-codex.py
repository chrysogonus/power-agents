#!/usr/bin/env python3
"""Codex adapter for the shared offline coding simulator."""
import runpy
from pathlib import Path


def main(mode, counter):
    simulator = runpy.run_path(str(Path(__file__).with_name('fake-coding-claude.py')))
    simulator['simulate']('codex', mode, counter)
