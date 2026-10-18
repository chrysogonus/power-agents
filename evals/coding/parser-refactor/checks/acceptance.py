import importlib.util
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'parser.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert module.parse_pair(' one ', '\ttwo\n') == ('one', 'two')
assert module.parse_pair('α', 'β') == ('α', 'β')
print('acceptance checks passed')
