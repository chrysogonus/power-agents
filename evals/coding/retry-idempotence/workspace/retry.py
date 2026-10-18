class Runner:
    def __init__(self):
        self.results = {}

    def run(self, operation_id, operation):
        result = operation()
        self.results[operation_id] = result
        return result
