"""
Script de diagnóstico para verificar la conexión con Supabase (schema PUBLIC)
Ejecutar: python test_supabase_connection.py
"""
import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions
import json

# Cargar variables de entorno
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_KEY = (os.getenv("SUPABASE_SERVICE_ROLE_KEY", "") or os.getenv("SUPABASE_SERVICE_ROLE", "")).strip()

print("=" * 60)
print("DIAGNÓSTICO DE CONEXIÓN A SUPABASE (SCHEMA PUBLIC)")
print("=" * 60)

# 1. Verificar variables de entorno
print("\n1. Variables de entorno:")
print(f"   SUPABASE_URL: {'✓ Configurada' if SUPABASE_URL else '✗ NO configurada'}")
print(f"   SUPABASE_KEY: {'✓ Configurada' if SUPABASE_KEY else '✗ NO configurada'}")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("\n❌ ERROR: Faltan variables de entorno")
    print("   Asegúrate de tener en tu archivo .env:")
    print("   SUPABASE_URL=https://tu-proyecto.supabase.co")
    print("   SUPABASE_SERVICE_ROLE_KEY=tu-clave-aqui")
    exit(1)

# 2. Intentar conexión (schema público por defecto)
print("\n2. Probando conexión con schema público (default)...")
try:
    supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(
            postgrest_client_timeout=120_000,
            storage_client_timeout=120_000
        )
    )
    print("   ✓ Conexión exitosa al schema público")
except Exception as e:
    print(f"   ✗ Error: {e}")
    exit(1)

# 3. Verificar tablas en schema 'public'
print("\n3. Verificando tablas en schema 'public'...")
tables_to_check = ["devices", "sessions", "metrics", "events", "window_reports", "device_config"]

existing_tables = []
missing_tables = []

for table in tables_to_check:
    try:
        resp = supabase.table(table).select("*").limit(1).execute()
        count = len(resp.data) if resp.data else 0
        print(f"   ✓ Tabla '{table}': accesible ({count} registros en muestra)")
        existing_tables.append(table)
    except Exception as e:
        error_msg = str(e)
        if "does not exist" in error_msg or "relation" in error_msg:
            print(f"   ✗ Tabla '{table}': NO EXISTE")
            missing_tables.append(table)
        else:
            print(f"   ✗ Tabla '{table}': {error_msg[:80]}")

if missing_tables:
    print(f"\n⚠️  TABLAS FALTANTES: {', '.join(missing_tables)}")
    print("\nPara crear las tablas faltantes, ejecuta este SQL en Supabase:")
    print("=" * 60)
    print("""
-- Copia y pega esto en el SQL Editor de Supabase:

CREATE TABLE IF NOT EXISTS public.devices (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  model TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.device_config (
  id SERIAL PRIMARY KEY,
  device_id INTEGER REFERENCES public.devices(id) ON DELETE CASCADE,
  ear_threshold FLOAT,
  mar_threshold FLOAT,
  pitch_deg_threshold FLOAT,
  consec_frames INTEGER,
  w_ear FLOAT,
  w_mar FLOAT,
  w_pose FLOAT,
  fusion_threshold FLOAT,
  use_python_alarm BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(device_id)
);

CREATE TABLE IF NOT EXISTS public.sessions (
  id SERIAL PRIMARY KEY,
  device_id INTEGER REFERENCES public.devices(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.metrics (
  id SERIAL PRIMARY KEY,
  session_id INTEGER REFERENCES public.sessions(id) ON DELETE CASCADE,
  ts TIMESTAMPTZ DEFAULT NOW(),
  ear FLOAT,
  mar FLOAT,
  yaw FLOAT,
  pitch FLOAT,
  roll FLOAT,
  fused_score FLOAT,
  closed_frames INTEGER,
  is_drowsy BOOLEAN,
  reason TEXT[]
);

CREATE TABLE IF NOT EXISTS public.events (
  id SERIAL PRIMARY KEY,
  session_id INTEGER REFERENCES public.sessions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  ts BIGINT,
  duration_s FLOAT,
  hand TEXT,
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.window_reports (
  id SERIAL PRIMARY KEY,
  session_id INTEGER REFERENCES public.sessions(id) ON DELETE CASCADE,
  window_s INTEGER,
  counts JSONB,
  durations JSONB,
  ts TIMESTAMPTZ DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_metrics_session_ts ON public.metrics(session_id, ts);
CREATE INDEX IF NOT EXISTS idx_events_session_type ON public.events(session_id, type);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON public.sessions(device_id);
    """)
    print("=" * 60)
    
    user_input = input("\n¿Continuar con las pruebas usando solo las tablas existentes? (s/n): ")
    if user_input.lower() != 's':
        exit(0)

# 4. Test de inserción en 'devices'
if "devices" in existing_tables:
    print("\n4. Probando inserción en tabla 'devices'...")
    try:
        test_device = {
            "name": "TEST_DEVICE_DIAGNOSTIC",
            "model": "TestModel"
        }
        resp = supabase.table("devices").upsert(test_device, on_conflict="name").execute()
        
        if resp.data and len(resp.data) > 0:
            device_id = resp.data[0]["id"]
            print(f"   ✓ Inserción exitosa! Device ID: {device_id}")
            
            # 5. Test de inserción en 'sessions'
            if "sessions" in existing_tables:
                print("\n5. Probando inserción en tabla 'sessions'...")
                try:
                    test_session = {"device_id": device_id}
                    resp = supabase.table("sessions").insert(test_session).execute()
                    if resp.data and len(resp.data) > 0:
                        session_id = resp.data[0]["id"]
                        print(f"   ✓ Session creada! ID: {session_id}")
                        
                        # 6. Test de inserción en 'metrics'
                        if "metrics" in existing_tables:
                            print("\n6. Probando inserción en tabla 'metrics'...")
                            try:
                                test_metric = {
                                    "session_id": session_id,
                                    "ear": 0.25,
                                    "mar": 0.35,
                                    "yaw": 5.0,
                                    "pitch": -10.0,
                                    "roll": 2.0,
                                    "fused_score": 0.15,
                                    "closed_frames": 5,
                                    "is_drowsy": False,
                                    "reason": ["Test"]
                                }
                                resp = supabase.table("metrics").insert(test_metric).execute()
                                if resp.data:
                                    print(f"   ✓ Métrica insertada exitosamente!")
                                    print(f"      Datos: {resp.data[0]}")
                                else:
                                    print(f"   ⚠ Respuesta vacía: {resp}")
                            except Exception as e:
                                print(f"   ✗ Error insertando métrica: {e}")
                        
                        # 7. Test de inserción en 'events'
                        if "events" in existing_tables:
                            print("\n7. Probando inserción en tabla 'events'...")
                            try:
                                test_event = {
                                    "session_id": session_id,
                                    "type": "test_event",
                                    "ts": 1234567890,
                                    "duration_s": 1.5,
                                    "payload": {"test": True}
                                }
                                resp = supabase.table("events").insert(test_event).execute()
                                if resp.data:
                                    print(f"   ✓ Evento insertado exitosamente!")
                                    print(f"      Datos: {resp.data[0]}")
                                else:
                                    print(f"   ⚠ Respuesta vacía: {resp}")
                            except Exception as e:
                                print(f"   ✗ Error insertando evento: {e}")
                        
                        # 8. Test de inserción en 'window_reports'
                        if "window_reports" in existing_tables:
                            print("\n8. Probando inserción en tabla 'window_reports'...")
                            try:
                                test_window = {
                                    "session_id": session_id,
                                    "window_s": 30,
                                    "counts": {"blinks": 5, "yawns": 2},
                                    "durations": {"avg_blink": 0.2}
                                }
                                resp = supabase.table("window_reports").insert(test_window).execute()
                                if resp.data:
                                    print(f"   ✓ Window report insertado exitosamente!")
                                    print(f"      Datos: {resp.data[0]}")
                                else:
                                    print(f"   ⚠ Respuesta vacía: {resp}")
                            except Exception as e:
                                print(f"   ✗ Error insertando window report: {e}")
                                
                    else:
                        print(f"   ⚠ Respuesta vacía al crear session: {resp}")
                except Exception as e:
                    print(f"   ✗ Error creando session: {e}")
        else:
            print(f"   ⚠ Respuesta vacía al crear device: {resp}")
            # Intentar buscar el device
            print("   Intentando buscar device existente...")
            resp = supabase.table("devices").select("*").eq("name", "TEST_DEVICE_DIAGNOSTIC").execute()
            if resp.data and len(resp.data) > 0:
                print(f"   ✓ Device encontrado: {resp.data[0]}")
            
    except Exception as e:
        print(f"   ✗ Error: {e}")

print("\n" + "=" * 60)
print("DIAGNÓSTICO COMPLETADO")
print("=" * 60)

if missing_tables:
    print("\n⚠️  ACCIÓN REQUERIDA:")
    print("   1. Crea las tablas faltantes ejecutando el SQL proporcionado arriba")
    print("   2. Vuelve a ejecutar este script para verificar")
elif existing_tables == tables_to_check:
    print("\n✅ TODO CORRECTO!")
    print("   - Todas las tablas existen")
    print("   - Las inserciones funcionan")
    print("   - Tu aplicación debería funcionar correctamente")
    print("\n📝 Siguiente paso:")
    print("   Actualiza tu app.py para usar schema 'public' (sin especificar schema)")
else:
    print("\nVerifica:")
    print("1. Que todas las tablas necesarias existan en schema 'public'")
    print("2. Que la SERVICE_ROLE_KEY tenga permisos suficientes")
    print("3. Las políticas RLS (Row Level Security) en Supabase")