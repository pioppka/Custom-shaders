#ifndef MRPIXEL_WATER
#define MRPIXEL_WATER

// Altura de las olas en bloques; p: XZ de mundo
float waveHeight(vec2 p, float t) {
    float h = 0.0;
    h += sin(dot(p, vec2(0.80, 0.60)) * 1.35 + t * 1.50) * 0.50;
    h += sin(dot(p, vec2(-0.55, 0.85)) * 2.10 + t * 2.05) * 0.30;
    h += sin(dot(p, vec2(0.95, -0.30)) * 3.40 + t * 2.70) * 0.16;
    h += sin(dot(p, vec2(-0.20, -0.98)) * 5.30 + t * 3.40) * 0.08;
    return h * 0.10 * WAVE_STRENGTH;
}

// Normal de las olas evaluada en el centro de la celda pixelada
vec3 waterWaveNormal(vec2 cell, float t) {
    float e = 1.0 / float(WATER_PIXELS);
    float h0 = waveHeight(cell, t);
    float hx = waveHeight(cell + vec2(e, 0.0), t);
    float hz = waveHeight(cell + vec2(0.0, e), t);
    return normalize(vec3((h0 - hx) / e, 1.0, (h0 - hz) / e));
}

vec3 waterBaseColor(vec3 texColor, vec3 tint) {
#if WATER_STYLE == 0
    vec3 c = mix(vec3(0.03, 0.42, 0.62), toLinear(tint) * vec3(0.55, 0.95, 1.10), 0.25);   // turquesa caricatura
#elif WATER_STYLE == 1
    vec3 c = toLinear(tint) * 1.15;                                                     // color del bioma
#else
    vec3 c = vec3(0.015, 0.16, 0.55);                                                   // azul profundo
#endif
    return c * (0.70 + 0.60 * luminance(texColor));
}

#endif
