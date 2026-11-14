#ifndef MRPIXEL_LIGHTMETER
#define MRPIXEL_LIGHTMETER

// Requiere: common, sky

// Medidor de luz: punto en la cara de arriba de los bloques con luz de bloque 0. Rojo: además poca luz de cielo.
// Amarillo: a cielo abierto

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

// rgb: color lineal (con brillo propio), a: cobertura (0 = nada)
vec4 lightMeterMark(vec3 playerPos, vec3 ng, vec2 lmcoord, vec3 dPdx, vec3 dPdy, vec2 dLdx, vec2 dLdy) {
#if LIGHT_METER == 0
    return vec4(0.0);
#else
    #if LIGHT_METER == 2
    if (max(heldBlockLightValue, heldBlockLightValue2) <= 0) return vec4(0.0);
    #endif
    if (!overworldSky() || ng.y < 0.9) return vec4(0.0);
    float fade = 1.0 - smoothstep(20.0, 28.0, length(playerPos));
    if (fade <= 0.0) return vec4(0.0);

    vec3 wp = playerPos + cameraPositionFract;
    if (abs(fract(wp.y + 0.5) - 0.5) > 0.01) return vec4(0.0);   // sólo a la altura de un bloque entero

    // punto de 4x4 texels con borde oscuro
    vec2 a = abs(floor(fract(wp.xz) * 16.0) - 7.5);
    bool fill = max(a.x, a.y) < 2.0 && min(a.x, a.y) < 1.0;
    bool ring = max(a.x, a.y) < 3.0 && min(a.x, a.y) < 2.0;
    if (!ring) return vec4(0.0);

    // lightmap en el centro de la cara
    vec2 d = floor(wp.xz) + 0.5 - wp.xz;
    float det = dPdx.x * dPdy.z - dPdx.z * dPdy.x;
    if (abs(det) < 1e-10) return vec4(0.0);
    vec2 st = vec2(d.x * dPdy.z - d.y * dPdy.x, dPdx.x * d.y - dPdx.z * d.x) / det;
    vec2 lm = (lmcoord + dLdx * st.x + dLdy * st.y) * 15.0;
    if (lm.x >= 0.5) return vec4(0.0);

    vec3 col = lm.y > 7.5 ? vec3(1.00, 0.72, 0.10) : vec3(1.00, 0.12, 0.08);
    return fill ? vec4(col * 1.2, fade) : vec4(vec3(0.0), fade * 0.55);
#endif
}

#endif
