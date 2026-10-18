import json


def reconcile(path):
    data = json.loads(path.read_text())
    data['managed'] = {'enabled': True}
    path.write_text(json.dumps(data, indent=2) + '\n')
