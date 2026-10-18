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

calls = []
r = module.Runner()
def operation():
    calls.append(1)
    return 0
assert r.run('one', operation) == 0
assert r.run('one', operation) == 0
assert len(calls) == 1, 'A retry repeated the side effect.'
assert r.run('two', operation) == 0
assert len(calls) == 2
nil_calls = []
def no_result():
    nil_calls.append(1)
    return None
assert r.run('nil', no_result) is None
assert r.run('nil', no_result) is None
assert nil_calls == [1], 'A None result was not cached.'
print('acceptance checks passed')
