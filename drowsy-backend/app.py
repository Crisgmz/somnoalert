# app.py
import os
import cv2
import numpy as np
import pygame
import asyncio
import json
import base64
import time
from typing import Optional, Dict, Any, List, Tuple
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import mediapipe as mp

# NUEVO: pipeline de drowsiness por eventos (parpadeo, micro-sueño, bostezo, pitch, frotado)
from detection.pipeline import DrowsinessPipeline

# =====================
# Config inicial (umbrales y pesos)
# =====================
EAR_THRESHOLD_BASE = float(os.getenv("EAR_THRESHOLD", "0.18"))
MAR_THRESHOLD_BASE = float(os.getenv("MAR_THRESHOLD", "0.60"))          # Bostezo
PITCH_DEG_THRESHOLD_BASE = float(os.getenv("PITCH_DEG_THRESHOLD", "20")) # Cabeceo (grados)
CONSEC_FRAMES_BASE = int(os.getenv("CONSEC_FRAMES", "50"))
FUSION_THRESHOLD_BASE = float(os.getenv("FUSION_THRESHOLD", "0.7"))

EAR_THRESHOLD_SIGNS = float(os.getenv("EAR_SIGNS_THRESHOLD", str(EAR_THRESHOLD_BASE + 0.03)))
EAR_THRESHOLD_NORMAL = float(os.getenv("EAR_NORMAL_THRESHOLD", str(EAR_THRESHOLD_SIGNS + 0.03)))

MAR_THRESHOLD_SIGNS = float(os.getenv("MAR_SIGNS_THRESHOLD", str(max(0.2, MAR_THRESHOLD_BASE - 0.05))))
MAR_THRESHOLD_NORMAL = float(os.getenv("MAR_NORMAL_THRESHOLD", str(max(0.2, MAR_THRESHOLD_SIGNS - 0.05))))

PITCH_THRESHOLD_SIGNS = float(os.getenv("PITCH_SIGNS_THRESHOLD", str(max(5.0, PITCH_DEG_THRESHOLD_BASE - 5.0))))
PITCH_THRESHOLD_NORMAL = float(os.getenv("PITCH_NORMAL_THRESHOLD", str(max(5.0, PITCH_THRESHOLD_SIGNS - 5.0))))

CONSEC_FRAMES_SIGNS = int(os.getenv("CONSEC_FRAMES_SIGNS", str(max(5, CONSEC_FRAMES_BASE - 10))))
CONSEC_FRAMES_NORMAL = int(os.getenv("CONSEC_FRAMES_NORMAL", str(max(2, CONSEC_FRAMES_SIGNS - 10))))

FUSION_THRESHOLD_SIGNS = float(os.getenv("FUSION_SIGNS_THRESHOLD", str(max(0.1, FUSION_THRESHOLD_BASE - 0.1))))
FUSION_THRESHOLD_NORMAL = float(os.getenv("FUSION_NORMAL_THRESHOLD", str(max(0.05, FUSION_THRESHOLD_SIGNS - 0.1))))

THRESHOLD_TIERS = ("normal", "signs", "drowsy")

THRESHOLD_PRESETS: Dict[str, Dict[str, Any]] = {
    "normal": {
        "ear": EAR_THRESHOLD_NORMAL,
        "mar": MAR_THRESHOLD_NORMAL,
        "pitch": PITCH_THRESHOLD_NORMAL,
        "fusion": FUSION_THRESHOLD_NORMAL,
        "consecFrames": CONSEC_FRAMES_NORMAL,
    },
    "signs": {
        "ear": EAR_THRESHOLD_SIGNS,
        "mar": MAR_THRESHOLD_SIGNS,
        "pitch": PITCH_THRESHOLD_SIGNS,
        "fusion": FUSION_THRESHOLD_SIGNS,
        "consecFrames": CONSEC_FRAMES_SIGNS,
    },
    "drowsy": {
        "ear": EAR_THRESHOLD_BASE,
        "mar": MAR_THRESHOLD_BASE,
        "pitch": PITCH_DEG_THRESHOLD_BASE,
        "fusion": FUSION_THRESHOLD_BASE,
        "consecFrames": CONSEC_FRAMES_BASE,
    },
}

EAR_THRESHOLD = THRESHOLD_PRESETS["drowsy"]["ear"]
MAR_THRESHOLD = THRESHOLD_PRESETS["drowsy"]["mar"]
PITCH_DEG_THRESHOLD = THRESHOLD_PRESETS["drowsy"]["pitch"]
CONSEC_FRAMES = THRESHOLD_PRESETS["drowsy"]["consecFrames"]
FUSION_THRESHOLD = THRESHOLD_PRESETS["drowsy"]["fusion"]


def _clamp(value: float, min_v: float, max_v: float) -> float:
    return max(min_v, min(max_v, value))


def _copy_thresholds() -> Dict[str, Dict[str, Any]]:
    return {
        tier: {
            "ear": float(cfg.get("ear", EAR_THRESHOLD_BASE)),
            "mar": float(cfg.get("mar", MAR_THRESHOLD_BASE)),
            "pitch": float(cfg.get("pitch", PITCH_DEG_THRESHOLD_BASE)),
            "fusion": float(cfg.get("fusion", FUSION_THRESHOLD_BASE)),
            "consecFrames": int(cfg.get("consecFrames", CONSEC_FRAMES_BASE)),
        }
        for tier, cfg in THRESHOLD_PRESETS.items()
    }


def _refresh_threshold_aliases() -> None:
    global EAR_THRESHOLD, MAR_THRESHOLD, PITCH_DEG_THRESHOLD, CONSEC_FRAMES, FUSION_THRESHOLD
    drowsy = THRESHOLD_PRESETS.get("drowsy", {})
    EAR_THRESHOLD = float(drowsy.get("ear", EAR_THRESHOLD_BASE))
    MAR_THRESHOLD = float(drowsy.get("mar", MAR_THRESHOLD_BASE))
    PITCH_DEG_THRESHOLD = float(drowsy.get("pitch", PITCH_DEG_THRESHOLD_BASE))
    FUSION_THRESHOLD = float(drowsy.get("fusion", FUSION_THRESHOLD_BASE))
    CONSEC_FRAMES = int(drowsy.get("consecFrames", CONSEC_FRAMES_BASE))


def _update_threshold_tier(tier: str, payload: Dict[str, Any]) -> None:
    if tier not in THRESHOLD_PRESETS:
        return

    cfg = dict(THRESHOLD_PRESETS[tier])

    if "ear" in payload:
        try:
            cfg["ear"] = _clamp(float(payload["ear"]), 0.05, 0.6)
        except (TypeError, ValueError):
            pass
    if "mar" in payload:
        try:
            cfg["mar"] = _clamp(float(payload["mar"]), 0.2, 1.5)
        except (TypeError, ValueError):
            pass
    if "pitch" in payload:
        try:
            cfg["pitch"] = _clamp(float(payload["pitch"]), 1.0, 90.0)
        except (TypeError, ValueError):
            pass
    if "fusion" in payload:
        try:
            cfg["fusion"] = _clamp(float(payload["fusion"]), 0.05, 1.0)
        except (TypeError, ValueError):
            pass
    if "consecFrames" in payload:
        try:
            cfg["consecFrames"] = max(1, int(payload["consecFrames"]))
        except (TypeError, ValueError):
            pass

    THRESHOLD_PRESETS[tier] = cfg
    if tier == "drowsy":
        _refresh_threshold_aliases()


def _sync_drowsy_map() -> None:
    THRESHOLD_PRESETS["drowsy"] = {
        "ear": EAR_THRESHOLD,
        "mar": MAR_THRESHOLD,
        "pitch": PITCH_DEG_THRESHOLD,
        "fusion": FUSION_THRESHOLD,
        "consecFrames": CONSEC_FRAMES,
    }


STAGE_LABELS = {
    "normal": "Normal",
    "signs": "Signos de somnolencia",
    "drowsy": "Somnolencia",
}


def evaluate_drowsiness_stage(
    ear: Optional[float],
    mar: Optional[float],
    pitch: Optional[float],
    fused_score: Optional[float],
    closed_frames_count: int,
) -> Tuple[str, List[str]]:
    stage = "normal"
    stage_reasons: List[str] = []

    for tier in THRESHOLD_TIERS:
        if tier == "normal":
            continue

        cfg = THRESHOLD_PRESETS.get(tier, {})
        tier_label = STAGE_LABELS.get(tier, tier)
        tier_reasons: List[str] = []

        ear_thr = cfg.get("ear")
        if ear is not None and ear_thr is not None and ear <= ear_thr:
            tier_reasons.append(f"{tier_label}: EAR ≤ {ear_thr:.2f}")

        mar_thr = cfg.get("mar")
        if mar is not None and mar_thr is not None and mar >= mar_thr:
            tier_reasons.append(f"{tier_label}: MAR ≥ {mar_thr:.2f}")

        pitch_thr = cfg.get("pitch")
        if pitch is not None and pitch_thr is not None and abs(pitch) >= pitch_thr:
            tier_reasons.append(f"{tier_label}: |Pitch| ≥ {pitch_thr:.1f}°")

        fusion_thr = cfg.get("fusion")
        if fused_score is not None and fusion_thr is not None and fused_score >= fusion_thr:
            tier_reasons.append(f"{tier_label}: Fusión ≥ {fusion_thr:.2f}")

        consec_thr = cfg.get("consecFrames")
        if consec_thr is not None and closed_frames_count >= consec_thr:
            tier_reasons.append(f"{tier_label}: Cerrados ≥ {consec_thr}")

        if tier_reasons:
            stage = tier
            stage_reasons = tier_reasons

    return stage, stage_reasons

# Pesos para la fusión (0..1, suman 1 idealmente)
W_EAR = float(os.getenv("W_EAR", "0.5"))
W_MAR = float(os.getenv("W_MAR", "0.3"))
W_POSE = float(os.getenv("W_POSE", "0.2"))

USE_PYTHON_ALARM = os.getenv("USE_PYTHON_ALARM", "1") == "1"

# =====================
# Configuración de video
# =====================
CAMERA_INDEX = int(os.getenv("CAMERA_INDEX", "0"))
CAMERA_WIDTH = int(os.getenv("CAMERA_WIDTH", "1280"))
CAMERA_HEIGHT = int(os.getenv("CAMERA_HEIGHT", "720"))
CAMERA_FPS = int(os.getenv("CAMERA_FPS", "30"))
FRAME_ORIENTATION = os.getenv("FRAME_ORIENTATION", "none").lower()
CAMERA_CODEC = os.getenv("CAMERA_CODEC", "MJPG").upper()

_ENV_CODECS = [c.strip().upper() for c in os.getenv("CAMERA_CODECS", "MJPG,YUY2,H264,XVID").split(",") if c.strip()]

def _unique_sequence(seq: List[Any]) -> List[Any]:
    seen = set()
    out = []
    for item in seq:
        key = tuple(item) if isinstance(item, (list, tuple)) else item
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out

PREFERRED_CODECS: List[str] = _unique_sequence([CAMERA_CODEC] + _ENV_CODECS)

DEFAULT_RESOLUTIONS: List[Tuple[int, int]] = _unique_sequence([
    (CAMERA_WIDTH, CAMERA_HEIGHT),
    (1920, 1080),
    (1600, 900),
    (1280, 720),
    (1024, 768),
    (800, 600),
    (640, 480),
])

PREFERRED_FPS: List[int] = sorted({CAMERA_FPS, 60, 30, 24}, reverse=True)

CAPTURE_BACKEND = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY

config_lock = asyncio.Lock()
camera_reset_event = asyncio.Event()

CURRENT_VIDEO_INFO: Dict[str, Any] = {
    "index": None,
    "width": None,
    "height": None,
    "fps": None,
    "codec": None,
    "orientation": FRAME_ORIENTATION,
}


def _normalize_orientation(value: str) -> str:
    allowed = {"none", "flip_h", "flip_v", "rotate180", "rotate_180", "mirror", "mirror_h"}
    value = (value or "none").lower()
    if value in ("mirror", "mirror_h"):
        return "flip_h"
    if value == "rotate_180":
        return "rotate180"
    return value if value in allowed else "none"


def _config_dict() -> Dict[str, Any]:
    """Snapshot del estado actual de configuración para exponer vía API."""
    return {
        "EAR_THRESHOLD": EAR_THRESHOLD,
        "MAR_THRESHOLD": MAR_THRESHOLD,
        "PITCH_DEG_THRESHOLD": PITCH_DEG_THRESHOLD,
        "CONSEC_FRAMES": CONSEC_FRAMES,
        "W_EAR": W_EAR,
        "W_MAR": W_MAR,
        "W_POSE": W_POSE,
        "FUSION_THRESHOLD": FUSION_THRESHOLD,
        "USE_PYTHON_ALARM": USE_PYTHON_ALARM,
        "thresholds": _copy_thresholds(),
        "thresholdOrder": list(THRESHOLD_TIERS),
        "camera": {
            "requested": {
                "index": CAMERA_INDEX,
                "width": CAMERA_WIDTH,
                "height": CAMERA_HEIGHT,
                "fps": CAMERA_FPS,
                "codec": CAMERA_CODEC,
                "orientation": FRAME_ORIENTATION,
            },
            "active": CURRENT_VIDEO_INFO.copy(),
            "options": {
                "codecs": PREFERRED_CODECS,
                "resolutions": [[int(w), int(h)] for (w, h) in DEFAULT_RESOLUTIONS],
                "fps": PREFERRED_FPS,
            },
        },
    }


def _update_preferred_video(codec: Optional[str] = None, resolution: Optional[Tuple[int, int]] = None, fps: Optional[int] = None) -> None:
    global PREFERRED_CODECS, DEFAULT_RESOLUTIONS, PREFERRED_FPS

    if codec:
        codec = codec.upper()
        PREFERRED_CODECS = _unique_sequence([codec] + PREFERRED_CODECS)
    if resolution:
        DEFAULT_RESOLUTIONS = _unique_sequence([resolution] + DEFAULT_RESOLUTIONS)
    if fps:
        PREFERRED_FPS = sorted(set(PREFERRED_FPS + [fps]), reverse=True)


def apply_orientation(frame: np.ndarray, orientation: str) -> np.ndarray:
    orient = _normalize_orientation(orientation)
    if orient == "flip_h":
        return cv2.flip(frame, 1)
    if orient == "flip_v":
        return cv2.flip(frame, 0)
    if orient == "rotate180":
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def _camera_index_candidates(primary: int) -> List[int]:
    primary = max(0, int(primary))
    order = [primary]
    for idx in range(0, 6):
        if idx not in order:
            order.append(idx)
    return order


def _open_camera_device(index_candidates: List[int], codecs: List[str], resolutions: List[Tuple[int, int]], fps: int) -> Tuple[Optional[cv2.VideoCapture], Dict[str, Any]]:
    """Intenta abrir una cámara siguiendo las preferencias provistas."""
    info: Dict[str, Any] = {
        "index": None,
        "codec": None,
        "width": None,
        "height": None,
        "fps": fps,
    }

    for idx in index_candidates:
        cap = cv2.VideoCapture(idx, CAPTURE_BACKEND)
        if not cap or not cap.isOpened():
            if cap:
                cap.release()
            continue

        print(f"🔎 Probando cámara {idx}")
        for codec in codecs:
            try:
                fourcc = cv2.VideoWriter_fourcc(*codec)
            except Exception:
                fourcc = 0
            if fourcc:
                cap.set(cv2.CAP_PROP_FOURCC, fourcc)

            if fps:
                cap.set(cv2.CAP_PROP_FPS, fps)

            for (width, height) in resolutions:
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

                # leer algunos frames para estabilizar
                ok = False
                frame = None
                for _ in range(3):
                    ok, frame = cap.read()
                    if ok and frame is not None:
                        break
                    time.sleep(0.01)

                if not ok or frame is None:
                    continue

                h, w = frame.shape[:2]
                if w <= 0 or h <= 0:
                    continue

                info.update({
                    "index": idx,
                    "codec": codec,
                    "width": w,
                    "height": h,
                    "fps": fps,
                })
                print(f"✅ Cámara {idx} configurada: {w}x{h} @{fps}fps codec {codec}")
                return cap, info

        print(f"⚠️ No se pudo configurar cámara {idx}")
        cap.release()

    print("❌ No se encontró cámara disponible")
    return None, info

# Landmarks MP FaceMesh
LEFT_EYE_IDX  = [33, 160, 158, 133, 153, 144]
RIGHT_EYE_IDX = [362, 385, 387, 263, 373, 380]

# Boca (conjunto estándar para MAR)
MOUTH_L_CORNER = 61
MOUTH_R_CORNER = 291
MOUTH_TOP_IN   = 13
MOUTH_BOT_IN   = 14
MOUTH_TOP_OUT1 = 81
MOUTH_BOT_OUT1 = 311
MOUTH_TOP_OUT2 = 78
MOUTH_BOT_OUT2 = 308

# PnP: índices útiles
PNP_NOSE_TIP = 4
PNP_CHIN     = 152
PNP_LEYE_OUT = 263
PNP_REYE_OUT = 33
PNP_LMOUTH   = 291
PNP_RMOUTH   = 61

# =====================
# FaceMesh
# =====================
mp_face = mp.solutions.face_mesh
face_mesh = mp_face.FaceMesh(
    static_image_mode=False,
    max_num_faces=1,
    refine_landmarks=True,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

# =====================
# Alarma opcional Python
# =====================
if USE_PYTHON_ALARM:
    try:
        pygame.mixer.init()
        pygame.mixer.music.load("alarma.mp3")
    except Exception as e:
        print("No se pudo cargar alarma.mp3:", e)
        USE_PYTHON_ALARM = False

# =====================
# Utilidades geométricas
# =====================
def dist(a, b):
    return np.linalg.norm(a - b)

def eye_aspect_ratio(landmarks, idxs, frame_w, frame_h):
    pts = []
    for i in idxs:
        lm = landmarks[i]
        pts.append(np.array([int(lm.x * frame_w), int(lm.y * frame_h)], dtype=np.float32))
    A = dist(pts[1], pts[5])
    B = dist(pts[2], pts[4])
    C = dist(pts[0], pts[3]) + 1e-6
    return (A + B) / (2.0 * C)

def mouth_aspect_ratio(landmarks, w, h):
    """MAR clásico usando varios pares verticales / ancho de boca."""
    def p(idx):
        lm = landmarks[idx]
        return np.array([lm.x * w, lm.y * h], dtype=np.float32)
    v1 = dist(p(MOUTH_TOP_IN),  p(MOUTH_BOT_IN))
    v2 = dist(p(MOUTH_TOP_OUT1),p(MOUTH_BOT_OUT1))
    v3 = dist(p(MOUTH_TOP_OUT2),p(MOUTH_BOT_OUT2))
    vertical = (v1 + v2 + v3) / 3.0
    horizontal = dist(p(MOUTH_L_CORNER), p(MOUTH_R_CORNER)) + 1e-6
    return vertical / horizontal

def estimate_head_pose(landmarks, w, h):
    """
    Estima yaw/pitch/roll (grados) con solvePnP usando 6 puntos.
    Convención: yaw (+ izquierda), pitch (+ arriba), roll (+ CW).
    """
    def p2d(idx):
        lm = landmarks[idx]
        return (lm.x * w, lm.y * h)

    image_points = np.array([
        p2d(PNP_NOSE_TIP),   # Nose tip
        p2d(PNP_CHIN),       # Chin
        p2d(PNP_LEYE_OUT),   # Left eye left corner (desde cámara)
        p2d(PNP_REYE_OUT),   # Right eye right corner
        p2d(PNP_LMOUTH),     # Left mouth corner
        p2d(PNP_RMOUTH)      # Right mouth corner
    ], dtype=np.float32)

    # Modelo 3D simplificado (en mm, aproximado al cráneo genérico)
    model_points = np.array([
        (0.0,   0.0,   0.0),     # Nose tip
        (0.0, -90.0, -25.0),     # Chin
        (-60.0, 40.0, -50.0),    # Left eye (desde el sujeto)
        (60.0,  40.0, -50.0),    # Right eye
        (-40.0,-30.0, -50.0),    # Left mouth
        (40.0, -30.0, -50.0)     # Right mouth
    ], dtype=np.float32)

    focal_length = w
    center = (w / 2, h / 2)
    camera_matrix = np.array([
        [focal_length, 0, center[0]],
        [0, focal_length, center[1]],
        [0, 0, 1]], dtype=np.float32)
    dist_coeffs = np.zeros((4, 1), dtype=np.float32)

    ok, rvec, tvec = cv2.solvePnP(model_points, image_points, camera_matrix, dist_coeffs, flags=cv2.SOLVEPNP_EPNP)
    if not ok:
        return None, None, None

    R, _ = cv2.Rodrigues(rvec)
    # Extracción de Euler angles
    sy = np.sqrt(R[0,0]*R[0,0] + R[1,0]*R[1,0])
    singular = sy < 1e-6
    if not singular:
        pitch = np.degrees(np.arctan2(R[2,1], R[2,2]))
        yaw   = np.degrees(np.arctan2(-R[2,0], sy))
        roll  = np.degrees(np.arctan2(R[1,0], R[0,0]))
    else:
        pitch = np.degrees(np.arctan2(-R[1,2], R[1,1]))
        yaw   = np.degrees(np.arctan2(-R[2,0], sy))
        roll  = 0.0
    return yaw, pitch, roll

def clamp01(x):
    return max(0.0, min(1.0, x))

def frame_to_base64(frame):
    try:
        h, w = frame.shape[:2]
        if w > 1280:
            scale = 1280 / w
            frame = cv2.resize(frame, (int(w*scale), int(h*scale)))
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 90, cv2.IMWRITE_JPEG_PROGRESSIVE, 1])
        return base64.b64encode(buffer).decode('utf-8')
    except Exception as e:
        print(f"Error converting frame to base64: {e}")
        return None

def draw_landmarks_on_frame(frame, landmarks):
    try:
        f = frame.copy()
        h, w = f.shape[:2]
        for idx in LEFT_EYE_IDX + RIGHT_EYE_IDX + \
                   [MOUTH_L_CORNER, MOUTH_R_CORNER, MOUTH_TOP_IN, MOUTH_BOT_IN,
                    MOUTH_TOP_OUT1, MOUTH_BOT_OUT1, MOUTH_TOP_OUT2, MOUTH_BOT_OUT2]:
            if idx < len(landmarks):
                lm = landmarks[idx]
                x, y = int(lm.x*w), int(lm.y*h)
                cv2.circle(f, (x, y), 2, (0, 255, 0), -1)
        return f
    except Exception as e:
        print(f"Error drawing landmarks: {e}")
        return frame


def render_landmark_cloud(landmarks, width: int, height: int) -> np.ndarray:
    try:
        canvas = np.zeros((height, width, 3), dtype=np.uint8)
        canvas[:] = (16, 24, 40)
        color = (210, 255, 255)
        for lm in landmarks:
            x = int(lm.x * width)
            y = int(lm.y * height)
            if 0 <= x < width and 0 <= y < height:
                cv2.circle(canvas, (x, y), 2, color, -1, lineType=cv2.LINE_AA)
        return canvas
    except Exception as e:
        print(f"Error rendering landmark cloud: {e}")
        return np.zeros((height, width, 3), dtype=np.uint8)

# =====================
# FastAPI
# =====================
app = FastAPI(title="Drowsiness Detector")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Estado runtime
closed_frames = 0
last_ear: Optional[float] = None
last_mar: Optional[float] = None
last_yaw = last_pitch = last_roll = None
is_drowsy = False
running = True

# NUEVO: pipeline por eventos (parpadeo, micro-sueño, bostezo, frotado, cabeceo)
pipeline = DrowsinessPipeline()

# =====================
# REST: get/set config
# =====================
@app.get("/config")
def get_config():
    return _config_dict()


@app.post("/config")
async def set_config(cfg: dict):
    global EAR_THRESHOLD, MAR_THRESHOLD, PITCH_DEG_THRESHOLD, CONSEC_FRAMES
    global W_EAR, W_MAR, W_POSE, FUSION_THRESHOLD, USE_PYTHON_ALARM
    global CAMERA_INDEX, CAMERA_WIDTH, CAMERA_HEIGHT, CAMERA_FPS, CAMERA_CODEC, FRAME_ORIENTATION

    print(f"Nueva configuración: {cfg}")

    video_changed = False

    async with config_lock:
        thresholds_payload = cfg.get("thresholds")
        if isinstance(thresholds_payload, dict):
            for tier, values in thresholds_payload.items():
                if isinstance(values, dict):
                    _update_threshold_tier(tier, values)
            _refresh_threshold_aliases()

        aliases_changed = False
        if "EAR_THRESHOLD" in cfg or "earThreshold" in cfg:
            EAR_THRESHOLD = float(cfg.get("EAR_THRESHOLD", cfg.get("earThreshold", EAR_THRESHOLD)))
            aliases_changed = True
        if "MAR_THRESHOLD" in cfg:
            MAR_THRESHOLD = float(cfg["MAR_THRESHOLD"])
            aliases_changed = True
        if "PITCH_DEG_THRESHOLD" in cfg:
            PITCH_DEG_THRESHOLD = float(cfg["PITCH_DEG_THRESHOLD"])
            aliases_changed = True
        if "CONSEC_FRAMES" in cfg or "consecFrames" in cfg:
            CONSEC_FRAMES = int(cfg.get("CONSEC_FRAMES", cfg.get("consecFrames", CONSEC_FRAMES)))
            aliases_changed = True
        if "W_EAR" in cfg:
            W_EAR = float(cfg["W_EAR"])
        if "W_MAR" in cfg:
            W_MAR = float(cfg["W_MAR"])
        if "W_POSE" in cfg:
            W_POSE = float(cfg["W_POSE"])
        if "FUSION_THRESHOLD" in cfg:
            FUSION_THRESHOLD = float(cfg["FUSION_THRESHOLD"])
            aliases_changed = True

        if aliases_changed:
            _sync_drowsy_map()

        if "USE_PYTHON_ALARM" in cfg:
            USE_PYTHON_ALARM = bool(cfg["USE_PYTHON_ALARM"])

        if "cameraIndex" in cfg:
            idx = int(cfg["cameraIndex"])
            if idx != CAMERA_INDEX:
                CAMERA_INDEX = idx
                video_changed = True

        if "frameWidth" in cfg:
            width = int(cfg["frameWidth"])
            if width != CAMERA_WIDTH:
                CAMERA_WIDTH = max(160, width)
                video_changed = True

        if "frameHeight" in cfg:
            height = int(cfg["frameHeight"])
            if height != CAMERA_HEIGHT:
                CAMERA_HEIGHT = max(120, height)
                video_changed = True

        if "cameraFps" in cfg:
            fps = int(cfg["cameraFps"])
            if fps != CAMERA_FPS:
                CAMERA_FPS = max(5, fps)
                video_changed = True

        if "cameraCodec" in cfg:
            codec = str(cfg["cameraCodec"]).upper()[:4]
            if codec and codec != CAMERA_CODEC:
                CAMERA_CODEC = codec
                video_changed = True

        if "frameOrientation" in cfg:
            orient = _normalize_orientation(str(cfg["frameOrientation"]))
            if orient != FRAME_ORIENTATION:
                FRAME_ORIENTATION = orient
                video_changed = True

        _update_preferred_video(CAMERA_CODEC, (CAMERA_WIDTH, CAMERA_HEIGHT), CAMERA_FPS)

    if USE_PYTHON_ALARM:
        if not pygame.mixer.get_init():
            try:
                pygame.mixer.init()
                pygame.mixer.music.load("alarma.mp3")
            except Exception as exc:
                print("No se pudo inicializar alarma tras cambio de config:", exc)
                USE_PYTHON_ALARM = False
    elif pygame.mixer.get_init():
        pygame.mixer.music.stop()

    if video_changed:
        camera_reset_event.set()

    config_payload = _config_dict()
    asyncio.create_task(broadcast({"message_type": "config", "config": config_payload}))
    return {"ok": True, **config_payload}

# =====================
# WebSocket: métricas
# =====================
clients = set()

@app.websocket("/ws")
async def metrics_ws(ws: WebSocket):
    await ws.accept()
    clients.add(ws)
    print(f"Cliente WebSocket conectado. Total: {len(clients)}")
    try:
        while True:
            msg = await ws.receive_text()
            if msg == "ping":
                await ws.send_text("pong")
    except WebSocketDisconnect:
        print("Cliente WebSocket desconectado")
    finally:
        clients.discard(ws)

async def broadcast(payload: dict):
    if not clients:
        return
    dead = []
    message = json.dumps(payload)
    for c in clients:
        try:
            await c.send_text(message)
        except Exception as e:
            print(f"Error enviando a cliente: {e}")
            dead.append(c)
    for d in dead:
        clients.discard(d)

# =====================
# NUEVO: manejo de eventos del pipeline
# =====================
async def handle_event(e: dict):
    """
    Dispara alarma (opcional) en eventos críticos y reenvía el evento a los clientes.
    """
    global is_drowsy
    etype = e.get("type")

    # Alarma ante micro-sueño, cabeceo o bostezo prolongado
    if etype in ("micro_sleep", "pitch_down", "yawn"):
        is_drowsy = True
        if USE_PYTHON_ALARM and pygame.mixer.get_init():
            if not pygame.mixer.music.get_busy():
                pygame.mixer.music.play(-1)

    # Difundir cualquier evento (incluye report_window, eye_blink, frame_overlay)
    payload = {"message_type": "event", **e}
    await broadcast(payload)

# =====================
# Loop de cámara en segundo plano
# =====================
async def camera_loop():
    global closed_frames, last_ear, last_mar, last_yaw, last_pitch, last_roll, is_drowsy

    print("Iniciando loop de cámara...")
    cap: Optional[cv2.VideoCapture] = None
    frame_count = 0
    consecutive_failures = 0
    config_snapshot: Dict[str, Any] = {}

    try:
        while running:
            if cap is None or camera_reset_event.is_set():
                if cap is not None:
                    cap.release()
                    cap = None

                camera_reset_event.clear()

                async with config_lock:
                    snapshot = {
                        "index": CAMERA_INDEX,
                        "width": CAMERA_WIDTH,
                        "height": CAMERA_HEIGHT,
                        "fps": CAMERA_FPS,
                        "codec": CAMERA_CODEC,
                        "orientation": FRAME_ORIENTATION,
                    }

                indices = _camera_index_candidates(snapshot["index"])
                codecs = _unique_sequence([snapshot["codec"]] + PREFERRED_CODECS)
                resolutions = _unique_sequence([(snapshot["width"], snapshot["height"]) ] + DEFAULT_RESOLUTIONS)

                cap_candidate, info = _open_camera_device(indices, codecs, resolutions, snapshot["fps"])
                if cap_candidate is None:
                    CURRENT_VIDEO_INFO.update({**info, "orientation": snapshot["orientation"]})
                    await asyncio.sleep(1.0)
                    continue

                cap = cap_candidate
                config_snapshot = {**snapshot, **info}
                config_snapshot["orientation"] = snapshot["orientation"]
                CURRENT_VIDEO_INFO.update({**info, "orientation": snapshot["orientation"]})

                if info.get("codec") or info.get("width"):
                    _update_preferred_video(
                        info.get("codec"),
                        (info.get("width"), info.get("height")) if info.get("width") and info.get("height") else None,
                        info.get("fps"),
                    )

                frame_count = 0
                consecutive_failures = 0

            ok, frame = cap.read()
            if not ok:
                await asyncio.sleep(0.1)
                consecutive_failures += 1
                if consecutive_failures > 10:
                    print("⚠️ Se perdió la señal de video, reintentando...")
                    camera_reset_event.set()
                continue

            consecutive_failures = 0

            frame = apply_orientation(frame, config_snapshot.get("orientation", "none"))

            frame_count += 1
            h, w = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = face_mesh.process(rgb)

            ear = mar = None
            yaw = pitch = roll = None
            processed = frame.copy()
            reason: List[str] = []
            fused_score = None
            landmarks_preview = None
            drowsiness_stage = "normal"
            stage_reasons: List[str] = []

            if results.multi_face_landmarks:
                lms = results.multi_face_landmarks[0].landmark

                # EAR
                ear_left  = eye_aspect_ratio(lms, LEFT_EYE_IDX, w, h)
                ear_right = eye_aspect_ratio(lms, RIGHT_EYE_IDX, w, h)
                ear = (ear_left + ear_right) / 2.0

                # MAR
                mar = mouth_aspect_ratio(lms, w, h)

                # Head pose
                yaw, pitch, roll = estimate_head_pose(lms, w, h)

                processed = draw_landmarks_on_frame(frame, lms)
                landmarks_preview = render_landmark_cloud(lms, w, h)

                # Texto de depuración
                y0 = 28
                for label, val in [
                    ("EAR", ear), ("MAR", mar),
                    ("Yaw", yaw), ("Pitch", pitch), ("Roll", roll)
                ]:
                    if val is not None:
                        cv2.putText(processed, f'{label}: {val:.3f}', (10, y0),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                        y0 += 24

                # Lógica EAR: contador de ojos cerrados
                if ear is not None and ear < EAR_THRESHOLD:
                    closed_frames += 1
                    cv2.putText(processed, 'OJOS CERRADOS', (10, y0),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                    reason.append("EAR<thr")
                else:
                    closed_frames = 0
                    cv2.putText(processed, 'OJOS ABIERTOS', (10, y0),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                y0 += 26

                # ======= FUSIÓN DE SEÑALES =======
                # Normalizaciones simples 0..1
                # EAR_score: 1 (muy somnoliento) cuando ear << thr
                ear_score = 0.0
                if ear is not None:
                    ear_score = clamp01((EAR_THRESHOLD - ear) / max(1e-6, EAR_THRESHOLD*0.6))

                # MAR_score: 1 cuando mar >> thr (bostezo grande)
                mar_score = 0.0
                if mar is not None:
                    mar_score = clamp01((mar - MAR_THRESHOLD) / max(1e-6, MAR_THRESHOLD*0.8))
                    if mar > MAR_THRESHOLD:
                        reason.append("MAR>thr")

                # Pose_score: 1 cuando |pitch| excede umbral
                pose_score = 0.0
                if pitch is not None:
                    pose_score = clamp01((abs(pitch) - PITCH_DEG_THRESHOLD) / max(1e-6, PITCH_DEG_THRESHOLD))
                    if abs(pitch) > PITCH_DEG_THRESHOLD:
                        reason.append("Pitch>thr")

                fused_score = W_EAR*ear_score + W_MAR*mar_score + W_POSE*pose_score

                drowsiness_stage, stage_reasons = evaluate_drowsiness_stage(
                    ear,
                    mar,
                    pitch,
                    fused_score,
                    closed_frames,
                )
                for desc in stage_reasons:
                    if desc not in reason:
                        reason.append(desc)

                # Disparo por fusión O por contador de frames cerrados
                should_alarm = (
                    drowsiness_stage == "drowsy"
                    or (fused_score is not None and fused_score >= FUSION_THRESHOLD)
                    or closed_frames >= CONSEC_FRAMES
                )

                if should_alarm:
                    is_drowsy = True
                    cv2.putText(processed, 'ALERTA DE SOMNOLENCIA!', (10, y0),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 3)
                    if USE_PYTHON_ALARM and pygame.mixer.get_init():
                        if not pygame.mixer.music.get_busy():
                            pygame.mixer.music.play(-1)
                else:
                    if is_drowsy:
                        is_drowsy = False
                        if USE_PYTHON_ALARM and pygame.mixer.get_init():
                            pygame.mixer.music.stop()

            else:
                processed = frame.copy()
                cv2.putText(processed, 'NO SE DETECTA ROSTRO',
                            (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                fused_score = fused_score if fused_score is not None else 0.0
                reason.append("Sin rostro detectado")

            # Actualizar últimas métricas
            last_ear = float(ear) if ear is not None else None
            last_mar = float(mar) if mar is not None else None
            last_yaw = float(yaw) if yaw is not None else None
            last_pitch = float(pitch) if pitch is not None else None
            last_roll = float(roll) if roll is not None else None

            # Frames a base64
            raw_b64 = frame_to_base64(frame)
            proc_b64 = frame_to_base64(processed)

            # Payload de métricas/preview (se mantiene como antes)
            if frame_count % 5 == 0:
                active_camera = {k: v for k, v in CURRENT_VIDEO_INFO.items()}
                if active_camera.get("orientation") is None:
                    active_camera["orientation"] = FRAME_ORIENTATION

                camera_config = {
                    "active": active_camera,
                    "requested": {
                        "index": CAMERA_INDEX,
                        "width": CAMERA_WIDTH,
                        "height": CAMERA_HEIGHT,
                        "fps": CAMERA_FPS,
                        "codec": CAMERA_CODEC,
                        "orientation": FRAME_ORIENTATION,
                    },
                    "options": {
                        "codecs": PREFERRED_CODECS,
                        "resolutions": [[int(w), int(h)] for (w, h) in DEFAULT_RESOLUTIONS],
                        "fps": PREFERRED_FPS,
                    },
                }

                config_payload = {
                    "usePythonAlarm": USE_PYTHON_ALARM,
                    "camera": camera_config,
                }

                fused_value = round(fused_score, 3) if fused_score is not None else None

                threshold_snapshot = _copy_thresholds()
                mesh_b64 = frame_to_base64(landmarks_preview) if landmarks_preview is not None else None
                stage_reasons = list(dict.fromkeys(stage_reasons))
                reason = list(dict.fromkeys(reason))

                payload = {
                    "message_type": "metrics",
                    "ear": round(last_ear, 4) if last_ear is not None else None,
                    "mar": round(last_mar, 4) if last_mar is not None else None,
                    "yaw": round(last_yaw, 2) if last_yaw is not None else None,
                    "pitch": round(last_pitch, 2) if last_pitch is not None else None,
                    "roll": round(last_roll, 2) if last_roll is not None else None,
                    "closedFrames": closed_frames,
                    "threshold": EAR_THRESHOLD,
                    "consecFrames": CONSEC_FRAMES,
                    "thresholds": threshold_snapshot,
                    "thresholdOrder": list(THRESHOLD_TIERS),
                    "weights": {"ear": W_EAR, "mar": W_MAR, "pose": W_POSE},
                    "isDrowsy": is_drowsy,
                    "drowsinessLevel": drowsiness_stage,
                    "stageReasons": stage_reasons,
                    "fusedScore": fused_value,
                    "reason": reason,
                    "rawFrame": raw_b64,
                    "processedFrame": proc_b64,
                    "landmarksFrame": mesh_b64,
                    "config": config_payload,
                }
                await broadcast(payload)

            # === NUEVO: pipeline de eventos de somnolencia (usa el frame BGR crudo) ===
            try:
                events = pipeline.step(frame)
                if events:
                    for e in events:
                        await handle_event(e)
            except Exception as ex:
                print(f"[pipeline] error: {ex}")

            await asyncio.sleep(0.033)
    finally:
        cap.release()
        if pygame.mixer.get_init():
            pygame.mixer.quit()
        print("Cámara liberada")

@app.on_event("startup")
async def on_start():
    print("🚀 Iniciando servidor de detección de somnolencia...")
    asyncio.create_task(camera_loop())

@app.on_event("shutdown")
async def on_shutdown():
    global running
    running = False
    print("🛑 Cerrando servidor...")

@app.get("/")
def root():
    return {
        "message": "Drowsiness backend running",
        "ws": "/ws",
        "config": "/config",
        "status": "OK",
        "camera": "Active" if running else "Inactive"
    }

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "camera_active": running,
        "clients_connected": len(clients),
        "current_config": _config_dict(),
    }

# Run:
# uvicorn app:app --host 0.0.0.0 --port 8000 --reload