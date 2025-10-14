import mediapipe as mp

_HANDS = mp.solutions.hands.Hands(
    static_image_mode=False, max_num_hands=2,
    min_detection_confidence=0.5, min_tracking_confidence=0.5
)

FINGERTIPS = [4,8,12,16,20]

def process_frame_bgr(frame_bgr):
    h, w = frame_bgr.shape[:2]
    rgb = frame_bgr[:, :, ::-1]
    res = _HANDS.process(rgb)
    out = []
    if res.multi_hand_landmarks:
        for hand in res.multi_hand_landmarks:
            pts = {i: (hand.landmark[i].x * w, hand.landmark[i].y * h) for i in FINGERTIPS}
            out.append(pts)
    return out  # lista de manos, cada una con tips
