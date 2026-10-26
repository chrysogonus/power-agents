import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True
workspace = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('subject', workspace / 'pages.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
paginate = module.paginate

items = list(range(10))
assert paginate(items, 1, 3) == {'items': [0, 1, 2], 'page': 1, 'total_pages': 4, 'has_next': True}
assert paginate(items, 4, 3) == {'items': [9], 'page': 4, 'total_pages': 4, 'has_next': False}, 'Last partial page.'
assert paginate(items, 2, 5)['has_next'] is False, 'An exactly full last page has no next page.'
assert paginate(items, 5, 3) == {'items': [], 'page': 5, 'total_pages': 4, 'has_next': False}, 'Past the end.'
assert paginate([], 1, 3) == {'items': [], 'page': 1, 'total_pages': 1, 'has_next': False}, 'An empty list has one page.'
assert paginate(tuple(items), 2, 3)['items'] == [3, 4, 5], 'Items are returned as a list.'
for page, per_page in ((0, 3), (-1, 3), (1, 0), (1, -2), (True, 3), (1, True), (1.0, 3), ('1', 3)):
    try:
        paginate(items, page, per_page)
    except ValueError:
        continue
    raise AssertionError(f'Accepted page={page!r}, per_page={per_page!r}.')
print('acceptance checks passed')
