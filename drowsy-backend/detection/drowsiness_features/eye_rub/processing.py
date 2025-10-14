import time
from ...utils.geom import euclid

class EyeRubDetector:
    def __init__(self, dist_px=40.0, hold_s=1.0, window_s=300.0):
        self.dist_px = dist_px; self.hold_s = hold_s; self.window_s = window_s
        self.win_t0 = time.time()
        self.active = {"left": None, "right": None}  # ts
        self.counts = {"left":0, "right":0}
        self.durations = {"left":[], "right":[]}

    def update(self, eyes, hands):
        now = time.time(); evts=[]
        eye_pts = {"left": eyes.get("L_ref"), "right": eyes.get("R_ref")}
        for side, eye_pt in eye_pts.items():
            touching = False
            if eye_pt and hands:
                for hand in hands:
                    for _, tip in hand.items():
                        if euclid(eye_pt, tip) < self.dist_px:
                            touching = True; break
                    if touching: break
            if touching and self.active[side] is None:
                self.active[side] = now
            if not touching and self.active[side] is not None:
                dt = now - self.active[side]; self.active[side] = None
                if dt > self.hold_s:
                    self.counts[side]+=1; self.durations[side].append(dt)
                    evts.append({"type":"eye_rub","ts":now,"hand":side,"duration_s":round(dt,2)})
        if now - self.win_t0 >= self.window_s:
            evts.append({"type":"report_window","ts":now,"window_s":self.window_s,
                         "counts":{"eye_rub": self.counts.copy()},
                         "durations":{"eye_rub": {k:[round(x,2) for x in v] for k,v in self.durations.items()}}})
            self.counts={"left":0,"right":0}; self.durations={"left":[],"right":[]}; self.win_t0=now
        return evts
