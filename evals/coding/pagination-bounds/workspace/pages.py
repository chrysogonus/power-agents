def paginate(items, page, per_page):
    """Return the items on a page."""
    start = page * per_page
    return items[start:start + per_page]
