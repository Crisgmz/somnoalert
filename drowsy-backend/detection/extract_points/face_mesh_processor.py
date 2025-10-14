import mediapipe as mp

_FACE = mp.solutions.face_mesh.FaceMesh(
    static_image_mode=False, max_num_faces=1,
    refine_landmarks=True, min_detection_confidence=0.5, min_tracking_confidence=0.5
)

# índices usados: ojos (159,145,385,374), iris refs (468,473), labios (13,14), mentón (17,199),
# nariz/ frent/ mejillas según FaceMesh canonical.
EYE_IDX = dict(L_up=159, L_down=145, R_up=385, R_down=374, L_ref=468, R_ref=473)
MOUTH_IDX = dict(lips_up=13, lips_down=14, chin_up=17, chin_down=199)

def process_frame_bgr(frame_bgr):
    h, w = frame_bgr.shape[:2]
    rgb = frame_bgr[:, :, ::-1]
    res = _FACE.process(rgb)
    if not res.multi_face_landmarks: return {}
    lm = res.multi_face_landmarks[0].landmark

    def pt(i): return (lm[i].x * w, lm[i].y * h)

    return {
        "eyes": {k: pt(v) for k, v in EYE_IDX.items()},
        "mouth": {k: pt(v) for k, v in MOUTH_IDX.items()},
        # añade aquí nariz, frente, mejillas si las usas en pitch
    }
