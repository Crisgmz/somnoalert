# detection/data_processing/head/head_processing.py
from ...utils.geom import euclid, between

def mouth_center(mouth: dict):
    """
    Centro geométrico simple de la boca a partir de labios superior/inferior.
    Espera claves: 'lips_up', 'lips_down'
    """
    ux, uy = mouth["lips_up"]
    dx, dy = mouth["lips_down"]
    return ((ux + dx) * 0.5, (uy + dy) * 0.5)

def head_distances(head: dict, mouth: dict):
    """
    Calcula distancias relevantes para inferir 'cabeza abajo (pitch)'.
    head: {
      'nose_tip': (x,y),
      'forehead': (x,y),
      'cheek_left': (x,y),
      'cheek_right': (x,y)
    }
    mouth: usa 'lips_up' y 'lips_down' para centro de boca.
    """
    nose = head["nose_tip"]
    fore = head["forehead"]
    cL   = head["cheek_left"]
    cR   = head["cheek_right"]
    mctr = mouth_center(mouth)

    d_nose_mouth = euclid(nose, mctr)
    d_nose_fore  = euclid(nose, fore)
    nose_between = between(nose[0], cL[0], cR[0])

    return {
        "nose_mouth": d_nose_mouth,
        "nose_forehead": d_nose_fore,
        "nose_between_cheeks": nose_between,
        "cheeks_span": abs(cR[0] - cL[0])
    }

def is_head_down(head: dict, mouth: dict, ratio_threshold: float = 1.0):
    """
    Regla base (como el repo analizado):
    - Cabeza abajo si la nariz está entre mejillas
    - y la distancia nariz-boca es menor que nariz-frente (o < ratio_threshold * nariz-frente)

    ratio_threshold te permite afinar sensibilidad (p.ej. 0.95 para ser más exigente).
    """
    m = head_distances(head, mouth)
    if not m["nose_between_cheeks"]:
        return False
    return m["nose_mouth"] < (ratio_threshold * (m["nose_forehead"] + 1e-6))

def head_metrics(head: dict, mouth: dict):
    """
    Devuelve un paquete de métricas útiles para logging/overlay.
    """
    m = head_distances(head, mouth)
    ratio = m["nose_mouth"] / (m["nose_forehead"] + 1e-6)
    return {
        **m,
        "nose_mouth_over_forehead_ratio": ratio
    }
