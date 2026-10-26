#!/usr/bin/env python3
"""Independent integrity checks for the local coding benchmark fixtures."""
import copy
import json
import runpy
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'evals/coding/tasks.json'


class CodingFixtureTests(unittest.TestCase):
    def test_baselines_and_reference_fixes(self):
        tasks = json.loads(MANIFEST.read_text())['tasks']
        self.assertEqual(len(tasks), 5)
        for task in tasks:
            with self.subTest(task=task['id']), tempfile.TemporaryDirectory() as temporary:
                work = Path(temporary) / 'work'
                shutil.copytree(MANIFEST.parent / task['snapshot'], work)
                for check, expected in [('verification', task['baseline_acceptance']),
                                        ('regression_verification', True)]:
                    result = subprocess.run(['python3', '-I', str(MANIFEST.parent / task[check][1]), str(work)], capture_output=True)
                    self.assertEqual(result.returncode == 0, expected, result.stderr.decode())
                applied = subprocess.run(['git', 'apply', str(MANIFEST.parent / task['reference_patch'])], cwd=work, capture_output=True)
                self.assertEqual(applied.returncode, 0, applied.stderr.decode())
                for check in ('verification', 'regression_verification'):
                    result = subprocess.run(['python3', '-I', str(MANIFEST.parent / task[check][1]), str(work)], capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_manifest_validation(self):
        load = runpy.run_path(str(ROOT / 'scripts/run-coding-evals.py'))['load_tasks']
        original = json.loads(MANIFEST.read_text())
        cases = [('id', 1), ('snapshot', '../outside'), ('verification', []), ('verification', ['missing-command']),
                 ('timeout_seconds', 0), ('timeout_seconds', float('nan')),
                 ('verification_timeout_seconds', -1), ('protected_paths', ['../outside'])]
        with tempfile.TemporaryDirectory() as temporary:
            fixtures = Path(temporary) / 'coding'
            shutil.copytree(MANIFEST.parent, fixtures)
            for field, value in cases:
                document = copy.deepcopy(original)
                document['tasks'][0][field] = value
                path = fixtures / 'tasks.json'
                path.write_text(json.dumps(document))
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    load(path, None)
            document = copy.deepcopy(original)
            document['tasks'].append(document['tasks'][0])
            path.write_text(json.dumps(document))
            with self.assertRaises(ValueError):
                load(path, None)


if __name__ == '__main__':
    unittest.main()
