def parse_pair(left, right):
    if not isinstance(left, str):
        raise TypeError('left must be text')
    left = left.strip()
    if not left:
        raise ValueError('left is empty')
    if not isinstance(right, str):
        raise TypeError('right must be text')
    right = right.strip()
    if not right:
        raise ValueError('right is empty')
    return left, right
