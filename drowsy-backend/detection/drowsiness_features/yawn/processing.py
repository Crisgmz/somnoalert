import time
from ...data_processing.mouth.mouth_processing import mouth_open

class YawnDetector:
    def __init__(self, hold_s=4.0, window_s=180.0):
        self.open_since = None
        self.hold_s = hold_s
        self.window_s = window_s
        self.win_t0 = time.time()
        self.yawns = []

    def update(self, mouth):
        now = time.time()
        evts = []
        is_open = mouth_open(mouth)
        if is_open and self.open_since is None:
            self.open_since = now
        if not is_open and self.open_since is not None:
            dt = now - self.open_since
            if dt > self.hold_s:
                self.yawns.append(dt)
                evts.append({"type": "yawn", "ts": now, "duration_s": round(dt,2)})
            self.open_since = None

        if now - self.win_t0 >= self.window_s:
            evts.append({
                "type":"report_window","ts":now,"window_s":self.window_s,
                "counts":{"yawns": len(self.yawns)},
                "durations":{"yawns":[round(x,2) for x in self.yawns]}
            })
            self.yawns = []; self.win_t0 = now
        return evts
