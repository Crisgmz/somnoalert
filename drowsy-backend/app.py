# app.py
import os
import cv2
import numpy as np
import pygame
import asyncio
import json
import base64
from typing import Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import mediapipe as mp

# NUEVO: pipeline de drowsiness por eventos (parpadeo, micro-sueño, bostezo, pitch, frotado)
from detection.pipeline import DrowsinessPipeline

# =====================
# Config inicial (umbrales y pesos)
# =====================
EAR_THRESHOLD = float(os.getenv("EAR_THRESHOLD", "0.18"))
MAR_THRESHOLD = float(os.getenv("MAR_THRESHOLD", "0.60"))          # Bostezo
PITCH_DEG_THRESHOLD = float(os.getenv("PITCH_DEG_THRESHOLD", "20")) # Cabeceo (grados)
CONSEC_FRAMES = int(os.getenv("CONSEC_FRAMES", "50"))

# Pesos para la fusión (0..1, suman 1 idealmente)
W_EAR = float(os.getenv("W_EAR", "0.5"))
W_MAR = float(os.getenv("W_MAR", "0.3"))
W_POSE = float(os.getenv("W_POSE", "0.2"))

# Umbral de activación de fusión (0..1)
FUSION_THRESHOLD = float(os.getenv("FUSION_THRESHOLD", "0.7"))

USE_PYTHON_ALARM = os.getenv("USE_PYTHON_ALARM", "1") == "1"

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
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
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
    return {
        "EAR_THRESHOLD": EAR_THRESHOLD,
        "MAR_THRESHOLD": MAR_THRESHOLD,
        "PITCH_DEG_THRESHOLD": PITCH_DEG_THRESHOLD,
        "CONSEC_FRAMES": CONSEC_FRAMES,
        "W_EAR": W_EAR, "W_MAR": W_MAR, "W_POSE": W_POSE,
        "FUSION_THRESHOLD": FUSION_THRESHOLD,
        "USE_PYTHON_ALARM": USE_PYTHON_ALARM
    }

@app.post("/config")
async def set_config(cfg: dict):
    global EAR_THRESHOLD, MAR_THRESHOLD, PITCH_DEG_THRESHOLD, CONSEC_FRAMES
    global W_EAR, W_MAR, W_POSE, FUSION_THRESHOLD, USE_PYTHON_ALARM
    print(f"Nueva configuración: {cfg}")
    EAR_THRESHOLD = float(cfg.get("EAR_THRESHOLD", cfg.get("earThreshold", EAR_THRESHOLD)))
    MAR_THRESHOLD = float(cfg.get("MAR_THRESHOLD", MAR_THRESHOLD))
    PITCH_DEG_THRESHOLD = float(cfg.get("PITCH_DEG_THRESHOLD", PITCH_DEG_THRESHOLD))
    CONSEC_FRAMES = int(cfg.get("CONSEC_FRAMES", cfg.get("consecFrames", CONSEC_FRAMES)))
    W_EAR = float(cfg.get("W_EAR", W_EAR))
    W_MAR = float(cfg.get("W_MAR", W_MAR))
    W_POSE = float(cfg.get("W_POSE", W_POSE))
    FUSION_THRESHOLD = float(cfg.get("FUSION_THRESHOLD", FUSION_THRESHOLD))
    USE_PYTHON_ALARM = bool(cfg.get("USE_PYTHON_ALARM", USE_PYTHON_ALARM))
    if USE_PYTHON_ALARM and not pygame.mixer.get_init():
        try:
            pygame.mixer.init()
            pygame.mixer.music.load("alarma.mp3")
        except Exception as exc:
            print("No se pudo inicializar alarma tras cambio de config:", exc)
            USE_PYTHON_ALARM = False
    elif not USE_PYTHON_ALARM and pygame.mixer.get_init():
        pygame.mixer.music.stop()
    return {"ok": True, **get_config()}

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
    await broadcast(e)

# =====================
# Loop de cámara en segundo plano
# =====================
async def camera_loop():
    global closed_frames, last_ear, last_mar, last_yaw, last_pitch, last_roll, is_drowsy

    print("Iniciando loop de cámara...")
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("❌ No se pudo abrir la cámara 0")
        for i in range(1, 4):
            print(f"Intentando cámara {i}...")
            cap = cv2.VideoCapture(i)
            if cap.isOpened():
                print(f"✅ Cámara {i} abierta")
                break
        else:
            print("❌ No se pudo abrir ninguna cámara")
            return

    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    candidates = [(1920, 1080), (1280, 720), (1024, 768), (800, 600), (640, 480)]
    selected = None
    for (W, H) in candidates:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, W)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, H)
        ok, test_frame = cap.read()
        if ok:
            h, w = test_frame.shape[:2]
            if abs(w - W) <= 16 and abs(h - H) <= 16:
                selected = (w, h)
                print(f"✅ Resolución seleccionada: {w}x{h}")
                break
    if selected is None:
        print("⚠️ No se pudo fijar una resolución alta, usando valores por defecto")
    cap.set(cv2.CAP_PROP_FPS, 30)
    print("✅ Cámara configurada")

    frame_count = 0

    try:
        while running:
            ok, frame = cap.read()
            if not ok:
                await asyncio.sleep(0.1)
                continue

            frame_count += 1
            h, w = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = face_mesh.process(rgb)

            ear = mar = None
            yaw = pitch = roll = None
            processed = frame.copy()
            reason = []

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

                # Disparo por fusión O por contador de frames cerrados
                should_alarm = fused_score >= FUSION_THRESHOLD or closed_frames >= CONSEC_FRAMES

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
                payload = {
                    "ear": round(last_ear, 4) if last_ear is not None else None,
                    "mar": round(last_mar, 4) if last_mar is not None else None,
                    "yaw": round(last_yaw, 2) if last_yaw is not None else None,
                    "pitch": round(last_pitch, 2) if last_pitch is not None else None,
                    "roll": round(last_roll, 2) if last_roll is not None else None,
                    "closedFrames": closed_frames,
                    "thresholds": {
                        "ear": EAR_THRESHOLD,
                        "mar": MAR_THRESHOLD,
                        "pitch": PITCH_DEG_THRESHOLD,
                        "fusion": FUSION_THRESHOLD
                    },
                    "weights": {"ear": W_EAR, "mar": W_MAR, "pose": W_POSE},
                    "isDrowsy": is_drowsy,
                    "fusedScore": round(
                        (W_EAR*clamp01((EAR_THRESHOLD - (last_ear or 0))/max(1e-6, EAR_THRESHOLD*0.6)) +
                         W_MAR*clamp01(((last_mar or 0)-MAR_THRESHOLD)/max(1e-6, MAR_THRESHOLD*0.8)) +
                         W_POSE*clamp01((abs(last_pitch or 0)-PITCH_DEG_THRESHOLD)/max(1e-6, PITCH_DEG_THRESHOLD))),
                         3),
                    "reason": reason,
                    "rawFrame": raw_b64,
                    "processedFrame": proc_b64
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
        "current_config": {
            "EAR_THRESHOLD": EAR_THRESHOLD,
            "MAR_THRESHOLD": MAR_THRESHOLD,
            "PITCH_DEG_THRESHOLD": PITCH_DEG_THRESHOLD,
            "CONSEC_FRAMES": CONSEC_FRAMES,
            "W_EAR": W_EAR, "W_MAR": W_MAR, "W_POSE": W_POSE,
            "FUSION_THRESHOLD": FUSION_THRESHOLD
        }
    }

# Run:
# uvicorn app:app --host 0.0.0.0 --port 8000 --reload