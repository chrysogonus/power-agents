import importlib.util
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'settings.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    path = Path(temporary) / 'settings.json'
    path.write_text(json.dumps({'managed': {'local': {'keep': [1, 2]}, 'enabled': False}, 'other': 7}))
    module.reconcile(path)
    data = json.loads(path.read_text())
    assert data == {'managed': {'enabled': True, 'retry_limit': 3, 'local': {'keep': [1, 2]}}, 'other': 7}
    first = path.read_bytes()
    module.reconcile(path)
    assert path.read_bytes() == first, 'Reconciliation is not idempotent.'
print('acceptance checks passed')
