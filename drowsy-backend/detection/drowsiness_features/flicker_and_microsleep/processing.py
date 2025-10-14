import time
from ...utils.timers import Stopwatch
from ...data_processing.eyes.eyes_processing import both_closed

class FlickerAndMicroSleep:
    def __init__(self, microsleep_s=2.0, report_window_s=60.0):
        self.closed_prev = False
        self.closed_since = None
        self.microsleep_s = microsleep_s
        self.window_s = report_window_s
        self.win_t0 = time.time()
        self.flickers = 0
        self.microsleeps = []

    def update(self, eyes):
        now = time.time()
        closed = both_closed(eyes)
        evts = []
        if closed and not self.closed_prev:
            self.closed_since = now
        if not closed and self.closed_prev:
            # transición cerrado->abierto: parpadeo
            dt = now - (self.closed_since or now)
            evts.append({"type": "eye_blink", "ts": now})
            if dt >= self.microsleep_s:
                self.microsleeps.append(dt)
                evts.append({"type": "micro_sleep", "ts": now, "duration_s": round(dt,2)})
            self.flickers += 1
            self.closed_since = None
        self.closed_prev = closed

        if now - self.win_t0 >= self.window_s:
            evts.append({
                "type": "report_window",
                "ts": now,
                "window_s": self.window_s,
                "counts": {"flickers": self.flickers, "microsleeps": len(self.microsleeps)},
                "durations": {"microsleeps": [round(x,2) for x in self.microsleeps]},
            })
            self.flickers = 0; self.microsleeps = []; self.win_t0 = now
        return evts
