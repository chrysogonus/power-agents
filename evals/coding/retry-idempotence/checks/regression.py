import importlib.util
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'retry.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

r = module.Runner()
assert r.run('one', lambda: 42) == 42
attempts = []
def flaky():
    attempts.append(1)
    if len(attempts) == 1:
        raise ValueError('try again')
    return None
try:
    r.run('failure', flaky)
except ValueError:
    pass
else:
    raise AssertionError('Failure was swallowed.')
assert r.run('failure', flaky) is None
assert len(attempts) == 2
print('regression checks passed')
