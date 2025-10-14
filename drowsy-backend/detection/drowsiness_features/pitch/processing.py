# detection/drowsiness_features/pitch/processing.py
import time
from ...data_processing.head.head_processing import is_head_down, head_metrics

class PitchDetector:
    """
    Detecta 'cabeza abajo' sostenida (cabeceo).
    - hold_s: segundos mínimos con cabeza abajo para disparar evento
    - window_s: tamaño de ventana para emitir reportes agregados
    - ratio_threshold: afinación de sensibilidad: nose_mouth < ratio_threshold * nose_forehead
    """
    def __init__(self, hold_s: float = 3.0, window_s: float = 180.0, ratio_threshold: float = 1.0):
        self.hold_s = hold_s
        self.window_s = window_s
        self.ratio_threshold = ratio_threshold

        self._down_since = None
        self._win_t0 = time.time()
        self._count = 0
        self._durations = []

    def update(self, head: dict, mouth: dict):
        """
        head: dict con nose_tip, forehead, cheek_left, cheek_right
        mouth: dict con lips_up, lips_down (para centro de boca)
        """
        now = time.time()
        evts = []
        down = is_head_down(head, mouth, ratio_threshold=self.ratio_threshold)

        # Inicio de estado "abajo"
        if down and self._down_since is None:
            self._down_since = now

        # Fin de estado "abajo" -> evaluar duración
        if (not down) and (self._down_since is not None):
            dt = now - self._down_since
            if dt >= self.hold_s:
                self._count += 1
                self._durations.append(dt)
                evts.append({
                    "type": "pitch_down",
                    "ts": now,
                    "duration_s": round(dt, 2)
                })
            self._down_since = None

        # Reporte por ventana
        if now - self._win_t0 >= self.window_s:
            evts.append({
                "type": "report_window",
                "ts": now,
                "window_s": self.window_s,
                "counts": {"pitch_down": self._count},
                "durations": {"pitch_down": [round(x,2) for x in self._durations]}
            })
            self._count = 0
            self._durations = []
            self._win_t0 = now

        # Métricas instantáneas (útil si quieres overlay HUD)
        try:
            m = head_metrics(head, mouth)
            evts.append({
                "type": "frame_overlay",
                "ts": now,
                "annotations": {
                    "pitch_ratio": round(m["nose_mouth_over_forehead_ratio"], 3),
                    "nose_between_cheeks": bool(m["nose_between_cheeks"])
                }
            })
        except Exception:
            pass

        return evts
