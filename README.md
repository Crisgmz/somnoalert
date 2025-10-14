# SomnoAlert

SomnoAlert es una solución de monitoreo de fatiga en tiempo real compuesta por un
backend en **FastAPI** con **OpenCV/Mediapipe** y un panel de control
**Flutter**. El backend captura video, calcula métricas faciales (EAR, MAR,
pitch) y genera eventos como parpadeos, bostezos o microsueños; el frontend
visualiza la secuencia de video procesada y permite ajustar los umbrales y
pesos que controlan la detección.

## Características clave

- Inicialización robusta de cámara: prueba múltiples índices, resoluciones,
  FPS y códecs hasta encontrar una combinación válida.
- Procesamiento en tiempo real de landmarks faciales, cálculo de métricas y
  fusión ponderada para activar la alarma.
- Sincronización bidireccional: el panel Flutter actualiza `/config` para
  modificar umbrales, pesos, orientación de cámara y estado de la alarma, y se
  mantienen actualizados los datos recibidos vía WebSocket (`/ws`).
- Registro de eventos (parpadeos, bostezos, microsueños, frotado de ojos y
  cabeceos) y visualización de históricos en la UI.

## Requisitos

- Python 3.10+
- [Poetry](https://python-poetry.org/) o `pip`
- OpenCV, Mediapipe, Pygame (instalados automáticamente desde
  `requirements.txt`)
- Flutter 3.13+

## Puesta en marcha del backend

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn drowsy-backend.app:app --reload
```

Variables de entorno relevantes:

| Variable              | Descripción                                           | Valor por defecto |
| --------------------- | ----------------------------------------------------- | ----------------- |
| `CAMERA_INDEX`        | Índice inicial a probar                               | `0`               |
| `CAMERA_WIDTH/HEIGHT` | Resolución objetivo                                   | `1280` / `720`    |
| `CAMERA_FPS`          | Cuadros por segundo preferidos                        | `30`              |
| `CAMERA_CODEC`        | Códec prioritario (cuatro letras, ej. `MJPG`)         | `MJPG`            |
| `FRAME_ORIENTATION`   | Transformaciones (`none`, `flip_h`, `flip_v`, `rotate180`) | `none`      |
| `EAR_THRESHOLD`       | Umbral de cierre ocular                               | `0.18`            |
| `MAR_THRESHOLD`       | Umbral de bostezo                                     | `0.60`            |
| `PITCH_DEG_THRESHOLD` | Umbral de cabeceo (grados)                            | `20`              |
| `FUSION_THRESHOLD`    | Umbral del puntaje fusionado                          | `0.7`             |

### Endpoints principales

- `GET /health`: estado general del sistema y cámara activa.
- `GET /config`: instantánea de la configuración vigente.
- `POST /config`: actualiza umbrales, pesos, parámetros de cámara y alarma.
- `WebSocket /ws`: stream en tiempo real con mensajes `message_type`:
  - `metrics`: métricas numéricas y fotograma procesado (base64).
  - `events`: eventos detectados (parpadeo, bostezo, etc.).
  - `config`: confirmaciones de cambios en configuración.

## Puesta en marcha del frontend

1. Instala el SDK de Flutter y ejecuta `flutter pub get` en la raíz del
   proyecto.
2. Inicia el backend (`uvicorn ...`).
3. Ajusta el archivo `lib/features/drowsy/state/drowsy_controller.dart` si
   necesitas cambiar la URL base (`_backendBaseUrl`).
4. Ejecuta la app en un emulador o dispositivo:

```bash
flutter run
```

### Análisis estático

- Backend: `python -m compileall drowsy-backend`
- Frontend: `flutter analyze` (requiere SDK instalado)

## Arquitectura de sincronización

1. El backend procesa cada frame, calcula métricas y publica actualizaciones
   por WebSocket junto con el fotograma codificado en Base64.
2. El controlador de Flutter (`DrowsyController`) escucha el WebSocket y
   propaga `DrowsyMetrics`, `DrowsyEvent` y la configuración activa a la UI.
3. Los controles de la interfaz envían cambios mediante `POST /config` que se
   reflejan inmediatamente en el backend; si se modifica un parámetro crítico
   (ej. orientación o códec), el backend reinicia la captura y notifica el
   nuevo estado por WebSocket.

Con esto tendrás un pipeline consistente para monitorear somnolencia y ajustar
los parámetros sin necesidad de reiniciar la aplicación.
