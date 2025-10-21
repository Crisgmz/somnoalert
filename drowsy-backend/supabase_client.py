# somno_supabase.py
# Cliente y utilidades Supabase para Somnoalert (esquema: somno)
# Requiere: pip install supabase==2.* python-dotenv tenacity

from __future__ import annotations
import os
import time
from typing import Any, Dict, Optional, List, Tuple

from dotenv import load_dotenv
from tenacity import retry, wait_exponential, stop_after_attempt, retry_if_exception_type
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions

# ------------------------------
# Carga de variables de entorno
# ------------------------------
load_dotenv(override=False)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
# Mantengo el nombre que usaste:
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip() or os.getenv("SUPABASE_SERVICE_ROLE", "").strip()

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError("Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY (o SERVICE_ROLE).")

# ------------------------------
# Cliente (schema = 'somno')
# ------------------------------
_client: Optional[Client] = None

def get_client() -> Client:
    global _client
    if _client is None:
        _client = create_client(
            SUPABASE_URL,
            SUPABASE_KEY,
            options=ClientOptions(
                schema="somno",                 # <— así no tienes que prefijar 'somno.' en cada tabla
                postgrest_client_timeout=120_000,
                storage_client_timeout=120_000,
            ),
        )
    return _client

# ------------------------------
# Utilidades comunes
# ------------------------------
class SBError(RuntimeError):
    pass

def _raise_if_error(resp) -> None:
    if hasattr(resp, "error") and resp.error:
        raise SBError(str(resp.error))

@retry(
    wait=wait_exponential(multiplier=0.3, min=0.5, max=6),
    stop=stop_after_attempt(4),
    retry=retry_if_exception_type((SBError, TimeoutError)),
    reraise=True,
)
def _insert(table: str, rows: Dict[str, Any] | List[Dict[str, Any]]):
    resp = get_client().table(table).insert(rows).execute()
    _raise_if_error(resp)
    return resp.data

@retry(
    wait=wait_exponential(multiplier=0.3, min=0.5, max=6),
    stop=stop_after_attempt(4),
    retry=retry_if_exception_type((SBError, TimeoutError)),
    reraise=True,
)
def _upsert(table: str, rows: Dict[str, Any] | List[Dict[str, Any]], on_conflict: str | None = None):
    q = get_client().table(table).upsert(rows)
    if on_conflict:
        q = q.on_conflict(on_conflict)
    resp = q.execute()
    _raise_if_error(resp)
    return resp.data

# ------------------------------
# Funciones de dominio
# ------------------------------
def ensure_device_and_session(device_name: str, device_model: str) -> Tuple[int, int]:
    """
    - Hace UPSERT del dispositivo por 'name' (idempotente).
    - Crea una sesión nueva ligada al device.
    Retorna: (device_id, session_id)
    """
    # upsert device (NO usar insert().on_conflict() — on_conflict es para upsert())
    dev_rows = _upsert(
        "devices",
        {"name": device_name, "model": device_model},
        on_conflict="name",
    )
    if not dev_rows:
        raise SBError("No se pudo upsert el dispositivo.")
    device_id = dev_rows[0]["id"]

    # crear session
    ses_rows = _insert("sessions", {"device_id": device_id})
    if not ses_rows:
        raise SBError("No se pudo crear la sesión.")
    session_id = ses_rows[0]["id"]

    return int(device_id), int(session_id)

def insert_metrics(session_id: int, payload: dict) -> None:
    """
    Inserta una fila en somno.metrics.
    Asegúrate que las columnas existen en tu tabla (ear, mar, yaw, pitch, roll, fused_score, closed_frames, is_drowsy, reason, ...).
    """
    data = {
        "session_id": session_id,
        "ear": payload.get("ear"),
        "mar": payload.get("mar"),
        "yaw": payload.get("yaw"),
        "pitch": payload.get("pitch"),
        "roll": payload.get("roll"),
        "fused_score": payload.get("fusedScore"),
        "closed_frames": payload.get("closedFrames"),
        "is_drowsy": payload.get("isDrowsy"),
        "reason": payload.get("reason"),
        # "raw_frame_b64": payload.get("rawFrame"),
        # "processed_frame_b64": payload.get("processedFrame"),
    }
    _insert("metrics", data)

def insert_event(session_id: int, evt: dict) -> None:
    """
    Inserta un evento puntual (blink, microsleep, yawn, face_rub, etc.).
    Si no se provee 'ts', la DB debe tener DEFAULT now() en la columna.
    """
    data = {
        "session_id": session_id,
        "type": evt.get("type"),
        "ts": evt.get("ts"),                     # opcional
        "duration_s": evt.get("duration_s"),
        "hand": evt.get("hand"),
        "payload": evt,                           # jsonb
    }
    _insert("events", data)

def insert_window_report(session_id: int, report: dict) -> None:
    """
    Reporte agregado por ventana (ej. cada 30–60 s).
    """
    data = {
        "session_id": session_id,
        "window_s": report.get("window_s"),
        "counts": report.get("counts"),
        "durations": report.get("durations"),
        # "ts": None  # si la columna tiene DEFAULT now(), no es necesario enviarla
    }
    _insert("window_reports", data)

def upsert_device_config(device_id: int, cfg: dict) -> None:
    """
    UPSERT de configuración del dispositivo (un registro por device_id).
    """
    data = {
        "device_id": device_id,
        "ear_threshold": cfg.get("EAR_THRESHOLD"),
        "mar_threshold": cfg.get("MAR_THRESHOLD"),
        "pitch_deg_threshold": cfg.get("PITCH_DEG_THRESHOLD"),
        "consec_frames": cfg.get("CONSEC_FRAMES"),
        "w_ear": cfg.get("W_EAR"),
        "w_mar": cfg.get("W_MAR"),
        "w_pose": cfg.get("W_POSE"),
        "fusion_threshold": cfg.get("FUSION_THRESHOLD"),
        "use_python_alarm": cfg.get("USE_PYTHON_ALARM"),
    }
    _upsert("device_config", data, on_conflict="device_id")

# ------------------------------
# Smoke test local
# ------------------------------
if __name__ == "__main__":
    print("Conectando a Supabase (somno)...")
    cli = get_client()
    print("OK")

    dev_id, ses_id = ensure_device_and_session("Raspberry #1", "RPI3")
    print("Device:", dev_id, "Session:", ses_id)

    now_ms = int(time.time() * 1000)
    insert_metrics(ses_id, {
        "ear": 0.17, "mar": 0.61, "yaw": 1.0, "pitch": -5.0, "roll": 0.2,
        "fusedScore": 0.73, "closedFrames": 42, "isDrowsy": True, "reason": "fusion>0.7"
    })
    insert_event(ses_id, {"type": "microsleep", "ts": now_ms, "duration_s": 0.3})
    insert_window_report(ses_id, {"window_s": 60, "counts": {"blink": 18}, "durations": {"microsleep": 0.9}})
    print("Inserciones OK.")
