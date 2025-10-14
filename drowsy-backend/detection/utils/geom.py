import math

def euclid(p1, p2):
    return math.hypot(p1[0]-p2[0], p1[1]-p2[1])

def between(x, a, b):  # utilidad simple
    return min(a,b) <= x <= max(a,b)
