import csv
import importlib.util
import io
import sys
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'export.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [
    ['plain', 'a,b', 'say "hi"', 'two\nlines', None, 42, -5, 1.5],
    ['=SUM(A1:A2)', '+1', '-1', '@cmd', '\tx', '\rx', 'safe=1', ''],
]
text = module.to_csv(rows)
assert text.endswith('\r\n') and '\n' not in text.replace('\r\n', '').replace('two\nlines', ''), 'Rows end with CRLF.'
parsed = list(csv.reader(io.StringIO(text, newline='')))
assert parsed[0] == ['plain', 'a,b', 'say "hi"', 'two\nlines', '', '42', '-5', '1.5'], parsed[0]
assert parsed[1] == ["'=SUM(A1:A2)", "'+1", "'-1", "'@cmd", "'\tx", "'\rx", 'safe=1', ''], parsed[1]
assert module.to_csv([]) == '', 'No rows, no output.'
print('acceptance checks passed')
