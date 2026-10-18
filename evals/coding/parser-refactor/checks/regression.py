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

for left, right, error, message in [(None, '', TypeError, 'left must be text'), ('', None, ValueError, 'left is empty'), ('ok', 2, TypeError, 'right must be text'), ('ok', ' ', ValueError, 'right is empty')]:
    try:
        module.parse_pair(left, right)
    except error as caught:
        assert str(caught) == message
    else:
        raise AssertionError('Expected exception was not raised.')
seen = []
class Text(str):
    def strip(self):
        seen.append(str(self))
        return super().strip()
assert module.parse_pair(Text(' a '), Text(' b ')) == ('a', 'b')
assert seen == [' a ', ' b ']
seen.clear()
try:
    module.parse_pair(Text(' '), Text(' b '))
except ValueError as caught:
    assert str(caught) == 'left is empty'
else:
    raise AssertionError('Empty subclass input was accepted.')
assert seen == [' '], 'Right was evaluated after a left-side failure.'
print('regression checks passed')
