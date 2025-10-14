from ...utils.geom import euclid

def mouth_open(mouth):
    lips = euclid(mouth["lips_up"], mouth["lips_down"])
    chin = euclid(mouth["chin_up"], mouth["chin_down"])
    return lips > chin  # criterio del repo analizado
