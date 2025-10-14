import time

class Stopwatch:
    def __init__(self): self._t0 = None
    def start(self): self._t0 = time.time()
    def stop(self): 
        if self._t0 is None: return 0.0
        dt = time.time() - self._t0; self._t0 = None; return dt
    def elapsed(self):
        return 0.0 if self._t0 is None else time.time() - self._t0
    def running(self): return self._t0 is not None
