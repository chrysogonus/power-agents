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
    path.write_text('{broken')
    before = path.read_bytes()
    try:
        module.reconcile(path)
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError('Invalid JSON was accepted.')
    assert path.read_bytes() == before
    path.write_text(json.dumps({'other': {'nested': 'preserve'}}))
    module.reconcile(path)
    data = json.loads(path.read_text())
    assert data['managed']['enabled'] is True
    assert data['other'] == {'nested': 'preserve'}
print('regression checks passed')
