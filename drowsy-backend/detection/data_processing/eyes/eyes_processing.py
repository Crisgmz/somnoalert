from ...utils.geom import euclid

def eyelid_distances(eyes):
    L = euclid(eyes["L_up"], eyes["L_down"])
    R = euclid(eyes["R_up"], eyes["R_down"])
    return L, R

def both_closed(eyes):
    L, R = eyelid_distances(eyes)
    # EAR proxy: distancia vertical baja implica cerrado; calibrable si agregas pupila-horizontal
    return L < 4.0 and R < 4.0  # px: ajusta a tu escala
