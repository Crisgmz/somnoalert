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

# =====================
# Config inicial
# =====================
EAR_THRESHOLD = float(os.getenv("EAR_THRESHOLD", "0.1"))
CONSEC_FRAMES = int(os.getenv("CONSEC_FRAMES", "50"))
USE_PYTHON_ALARM = os.getenv("USE_PYTHON_ALARM", "1") == "1"  # 1 = sonar alarma aquí

LEFT_EYE_IDX  = [33, 160, 158, 133, 153, 144]
RIGHT_EYE_IDX = [362, 385, 387, 263, 373, 380]

# =====================
# FaceMesh
# =====================
mp_face = mp.solutions.face_mesh
mp_drawing = mp.solutions.drawing_utils
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

def frame_to_base64(frame):
    """Convierte un frame de OpenCV a base64 para envío por WebSocket"""
    try:
        # Redimensionar para optimizar el envío
        height, width = frame.shape[:2]
        if width > 1080:
            scale = 1080 / width
            new_width = int(width * scale)
            new_height = int(height * scale)
            frame = cv2.resize(frame, (new_width, new_height))
        
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
        img_base64 = base64.b64encode(buffer).decode('utf-8')
        return img_base64
    except Exception as e:
        print(f"Error converting frame to base64: {e}")
        return None

def draw_landmarks_on_frame(frame, landmarks):
    """Dibuja los landmarks faciales en el frame"""
    try:
        frame_copy = frame.copy()
        h, w = frame_copy.shape[:2]
        
        # Dibujar puntos de los ojos
        for idx in LEFT_EYE_IDX + RIGHT_EYE_IDX:
            if idx < len(landmarks):
                lm = landmarks[idx]
                x = int(lm.x * w)
                y = int(lm.y * h)
                cv2.circle(frame_copy, (x, y), 2, (0, 255, 0), -1)
        
        # Dibujar contorno de los ojos
        left_eye_pts = []
        right_eye_pts = []
        
        for idx in LEFT_EYE_IDX:
            if idx < len(landmarks):
                lm = landmarks[idx]
                left_eye_pts.append([int(lm.x * w), int(lm.y * h)])
        
        for idx in RIGHT_EYE_IDX:
            if idx < len(landmarks):
                lm = landmarks[idx]
                right_eye_pts.append([int(lm.x * w), int(lm.y * h)])
        
        if left_eye_pts:
            cv2.polylines(frame_copy, [np.array(left_eye_pts)], True, (255, 0, 0), 2)
        if right_eye_pts:
            cv2.polylines(frame_copy, [np.array(right_eye_pts)], True, (255, 0, 0), 2)
            
        return frame_copy
    except Exception as e:
        print(f"Error drawing landmarks: {e}")
        return frame

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
    print(f"Recibiendo nueva configuración: {cfg}")
    if "EAR_THRESHOLD" in cfg:
        EAR_THRESHOLD = float(cfg["EAR_THRESHOLD"])
    if "CONSEC_FRAMES" in cfg:
        CONSEC_FRAMES = int(cfg["CONSEC_FRAMES"])
    if "earThreshold" in cfg:  
        EAR_THRESHOLD = float(cfg["earThreshold"])
    if "consecFrames" in cfg:  # Flutter envía con este nombre
        CONSEC_FRAMES = int(cfg["consecFrames"])
    
    print(f"Nueva configuración aplicada - EAR: {EAR_THRESHOLD}, Frames: {CONSEC_FRAMES}")
    return {"ok": True, "EAR_THRESHOLD": EAR_THRESHOLD, "CONSEC_FRAMES": CONSEC_FRAMES}

# =====================
# WebSocket: métricas
# =====================
clients = set()

@app.websocket("/ws")
async def metrics_ws(ws: WebSocket):
    await ws.accept()
    clients.add(ws)
    print(f"Cliente WebSocket conectado. Total clientes: {len(clients)}")
    try:
        while True:
            # Si el cliente envía algo, podríamos procesarlo (e.g. pausar, ping)
            message = await ws.receive_text()
            if message == "ping":
                await ws.send_text("pong")
    except WebSocketDisconnect:
        print("Cliente WebSocket desconectado")
    except Exception as e:
        print(f"Error en WebSocket: {e}")
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
# Loop de cámara en segundo plano
# =====================
async def camera_loop():
    global closed_frames, last_ear, is_drowsy
    
    print("Iniciando loop de cámara...")
    cap = cv2.VideoCapture(0)
    
    if not cap.isOpened():
        print("❌ No se pudo abrir la cámara 0")
        # Intentar con otras cámaras
        for i in range(1, 4):
            print(f"Intentando cámara {i}...")
            cap = cv2.VideoCapture(i)
            if cap.isOpened():
                print(f"✅ Cámara {i} abierta exitosamente")
                break
        else:
            print("❌ No se pudo abrir ninguna cámara")
            return

    # Configurar cámara
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    
    print("✅ Cámara configurada exitosamente")
    frame_count = 0

    try:
        while running:
            ok, frame = cap.read()
            if not ok:
                print("No se pudo leer frame de la cámara")
                await asyncio.sleep(0.1)
                continue

            frame_count += 1
            h, w = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = face_mesh.process(rgb)

            ear = None
            processed_frame = frame.copy()
            
            if results.multi_face_landmarks:
                landmarks = results.multi_face_landmarks[0].landmark
                ear_left  = eye_aspect_ratio(landmarks, LEFT_EYE_IDX, w, h)
                ear_right = eye_aspect_ratio(landmarks, RIGHT_EYE_IDX, w, h)
                ear = (ear_left + ear_right) / 2.0

                # Dibujar landmarks en el frame procesado
                processed_frame = draw_landmarks_on_frame(frame, landmarks)
                
                # Agregar texto con información
                cv2.putText(processed_frame, f'EAR: {ear:.3f}', 
                           (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv2.putText(processed_frame, f'Frames cerrados: {closed_frames}', 
                           (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

                if ear < EAR_THRESHOLD:
                    closed_frames += 1
                    cv2.putText(processed_frame, 'OJOS CERRADOS', 
                               (10, 90), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                    
                    if closed_frames >= CONSEC_FRAMES:
                        is_drowsy = True
                        cv2.putText(processed_frame, 'ALERTA DE SOMNOLENCIA!', 
                                   (10, 120), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 3)
                        
                        if USE_PYTHON_ALARM and pygame.mixer.get_init():
                            if not pygame.mixer.music.get_busy():
                                pygame.mixer.music.play(-1)
                else:
                    closed_frames = 0
                    if is_drowsy:  # Solo cambiar si estaba en alerta
                        is_drowsy = False
                        if USE_PYTHON_ALARM and pygame.mixer.get_init():
                            pygame.mixer.music.stop()
                    
                    cv2.putText(processed_frame, 'OJOS ABIERTOS', 
                               (10, 90), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            else:
                cv2.putText(processed_frame, 'NO SE DETECTA ROSTRO', 
                           (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)

            last_ear = float(ear) if ear is not None else None

            # Convertir frames a base64 para envío
            raw_frame_b64 = frame_to_base64(frame)
            processed_frame_b64 = frame_to_base64(processed_frame)

            # Enviar métricas al frontend cada 10 frames (optimización)
            if frame_count % 5 == 0:  # Enviar cada 5 frames para reducir carga
                payload = {
                    "ear": round(last_ear, 4) if last_ear is not None else None,
                    "closedFrames": closed_frames,
                    "threshold": EAR_THRESHOLD,
                    "consecFrames": CONSEC_FRAMES,
                    "isDrowsy": is_drowsy,
                    "rawFrame": raw_frame_b64,
                    "processedFrame": processed_frame_b64
                }
                await broadcast(payload)

            await asyncio.sleep(0.033)  # ~30 FPS
            
    except Exception as e:
        print(f"Error en camera_loop: {e}")
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
            "CONSEC_FRAMES": CONSEC_FRAMES
        }
    }

# Run:
# uvicorn app:app --host 0.0.0.0 --port 8000 --reload