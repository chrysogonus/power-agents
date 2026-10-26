import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'pages.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

items = [3, 1, 2]
module.paginate(items, 1, 2)
assert items == [3, 1, 2], 'The input was changed.'
module.paginate(('a', 'b'), 1, 1)
print('regression checks passed')
