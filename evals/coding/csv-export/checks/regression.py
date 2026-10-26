import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'export.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [['a', 1], ['b', 2]]
assert module.to_csv(rows).replace('\r\n', '\n') == 'a,1\nb,2\n'
assert rows == [['a', 1], ['b', 2]], 'The input was changed.'
print('regression checks passed')
