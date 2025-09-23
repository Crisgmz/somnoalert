# app.py
import os
import cv2
import numpy as np
import pygame
import asyncio
import json
from typing import Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import mediapipe as mp

# =====================
# Config inicial
# =====================
EAR_THRESHOLD = float(os.getenv("EAR_THRESHOLD", "0.20"))
CONSEC_FRAMES = int(os.getenv("CONSEC_FRAMES", "50"))
USE_PYTHON_ALARM = os.getenv("USE_PYTHON_ALARM", "1") == "1"  # 1 = sonar alarma aquí

LEFT_EYE_IDX  = [33, 160, 158, 133, 153, 144]
RIGHT_EYE_IDX = [362, 385, 387, 263, 373, 380]

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
    pygame.mixer.init()
    try:
        pygame.mixer.music.load("alarma.mp3")
    except Exception as e:
        print("No se pudo cargar alarma.mp3:", e)

def dist(a, b):
    return np.linalg.norm(a - b)

def eye_aspect_ratio(landmarks, idxs, frame_w, frame_h):
    pts = []
    for i in idxs:
        lm = landmarks[i]
        pts.append(np.array([int(lm.x * frame_w), int(lm.y * frame_h)]))
    A = dist(pts[1], pts[5])
    B = dist(pts[2], pts[4])
    C = dist(pts[0], pts[3]) + 1e-6  # Evitar división por cero
    return (A + B) / (2.0 * C)

# =====================
# FastAPI
# =====================
app = FastAPI(title="Drowsiness Detector")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # en prod restringe a tu dominio/app
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Estado runtime
closed_frames = 0
last_ear: Optional[float] = None
is_drowsy = False
running = True

# =====================
# REST: get/set config
# =====================
@app.get("/config")
def get_config():
    return {
        "EAR_THRESHOLD": EAR_THRESHOLD,
        "CONSEC_FRAMES": CONSEC_FRAMES,
        "USE_PYTHON_ALARM": USE_PYTHON_ALARM
    }

@app.post("/config")
async def set_config(cfg: dict):
    global EAR_THRESHOLD, CONSEC_FRAMES
    if "EAR_THRESHOLD" in cfg:
        EAR_THRESHOLD = float(cfg["EAR_THRESHOLD"])
    if "CONSEC_FRAMES" in cfg:
        CONSEC_FRAMES = int(cfg["CONSEC_FRAMES"])
    return {"ok": True, "EAR_THRESHOLD": EAR_THRESHOLD, "CONSEC_FRAMES": CONSEC_FRAMES}

# =====================
# WebSocket: métricas
# =====================
clients = set()

@app.websocket("/ws")
async def metrics_ws(ws: WebSocket):
    await ws.accept()
    clients.add(ws)
    try:
        while True:
            # Si el cliente envía algo, podríamos procesarlo (e.g. pausar, ping)
            _ = await ws.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        clients.discard(ws)

async def broadcast(payload: dict):
    if not clients:
        return
    dead = []
    for c in clients:
        try:
            await c.send_text(json.dumps(payload))
        except Exception:
            dead.append(c)
    for d in dead:
        clients.discard(d)

# =====================
# Loop de cámara en segundo plano
# =====================
async def camera_loop():
    global closed_frames, last_ear, is_drowsy
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("No se pudo abrir la cámara 0")
        return

    try:
        while running:
            ok, frame = cap.read()
            if not ok:
                await asyncio.sleep(0.02)
                continue

            h, w = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = face_mesh.process(rgb)

            ear = None
            if results.multi_face_landmarks:
                lm = results.multi_face_landmarks[0].landmark
                ear_left  = eye_aspect_ratio(lm, LEFT_EYE_IDX, w, h)
                ear_right = eye_aspect_ratio(lm, RIGHT_EYE_IDX, w, h)
                ear = (ear_left + ear_right) / 2.0

                if ear < EAR_THRESHOLD:
                    closed_frames += 1
                    if closed_frames >= CONSEC_FRAMES:
                        is_drowsy = True
                        if USE_PYTHON_ALARM and pygame.mixer.get_init():
                            if not pygame.mixer.music.get_busy():
                                pygame.mixer.music.play(-1)
                else:
                    closed_frames = 0
                    is_drowsy = False
                    if USE_PYTHON_ALARM and pygame.mixer.get_init():
                        if pygame.mixer.music.get_busy():
                            pygame.mixer.music.stop()

            last_ear = float(ear) if ear is not None else None

            # Enviar métricas al frontend
            payload = {
                "ear": round(last_ear, 4) if last_ear is not None else None,
                "closed_frames": closed_frames,
                "threshold": EAR_THRESHOLD,
                "consec_frames": CONSEC_FRAMES,
                "is_drowsy": is_drowsy,
            }
            await broadcast(payload)

            await asyncio.sleep(0.02)  # ~50 FPS / ajusta si quieres menos carga
    finally:
        cap.release()
        if pygame.mixer.get_init():
            pygame.mixer.quit()

@app.on_event("startup")
async def on_start():
    asyncio.create_task(camera_loop())

@app.get("/")
def root():
    return {"message": "Drowsiness backend running", "ws": "/ws", "config": "/config"}

# Run:
# uvicorn app:app --host 0.0.0.0 --port 8000
