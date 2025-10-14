# detection/pipeline.py
from .extract_points.face_mesh_processor import process_frame_bgr as face_pts
from .extract_points.hands_processor import process_frame_bgr as hands_pts
from .drowsiness_features.flicker_and_microsleep.processing import FlickerAndMicroSleep
from .drowsiness_features.yawn.processing import YawnDetector
from .drowsiness_features.eye_rub.processing import EyeRubDetector
from .drowsiness_features.pitch.processing import PitchDetector  # <— AÑADIR

class DrowsinessPipeline:
    def __init__(self):
        self.fms = FlickerAndMicroSleep(microsleep_s=2.0, report_window_s=60.0)
        self.yawn = YawnDetector(hold_s=4.0, window_s=180.0)
        self.rub  = EyeRubDetector(dist_px=40.0, hold_s=1.0, window_s=300.0)
        self.pitch = PitchDetector(hold_s=3.0, window_s=180.0, ratio_threshold=1.0)  # <— AÑADIR

    def step(self, frame_bgr):
        evts = []
        face = face_pts(frame_bgr) or {}
        hands = hands_pts(frame_bgr) or []

        eyes = face.get("eyes")
        mouth = face.get("mouth")
        head = face.get("head")

        if eyes:
            evts += self.fms.update(eyes)
            evts += self.rub.update(eyes, hands)
        if mouth:
            evts += self.yawn.update(mouth)
        if head and mouth:                       # <— REQUIERE head + mouth
            evts += self.pitch.update(head, mouth)

        return evts
