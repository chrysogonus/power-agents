def to_csv(rows):
    """Return rows (lists of values) as CSV text."""
    return "\n".join(",".join(str(value) for value in row) for row in rows) + "\n"
