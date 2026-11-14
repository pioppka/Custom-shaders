#ifndef MRPIXEL_CAUSTICS
#define MRPIXEL_CAUSTICS

// Requiere: common, sky, shadows (SHADOW_SAMPLING)

// Ondas: las 4 de water.glsl más 4 finas. xy vector de onda, z amplitud, w velocidad
const vec4 CAUSTIC_WAVES[8] = vec4[8](
    vec4(vec2(0.80, 0.60) * 1.35, 0.050, 1.50),
    vec4(vec2(-0.55, 0.85) * 2.10, 0.030, 2.05),
    vec4(vec2(0.95, -0.30) * 3.40, 0.016, 2.70),
    vec4(vec2(-0.20, -0.98) * 5.30, 0.008, 3.40),
    vec4(vec2(0.31, 0.95) * 2.70, 0.020, 2.30),
    vec4(vec2(-0.93, 0.37) * 3.90, 0.012, 2.76),
    vec4(vec2(0.60, -0.80) * 4.70, 0.009, 3.04),
    vec4(vec2(-0.72, -0.69) * 1.75, 0.032, 1.85));

// Hessiano de la altura de las olas en p: (xx, yy, xy)
vec3 causticHessian(vec2 p, float t) {
    vec3 h = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        vec4 w = CAUSTIC_WAVES[i];
        h -= w.z * sin(dot(p, w.xy) + t * w.w) * vec3(w.x * w.x, w.y * w.y, w.x * w.y);
    }
    return h * WAVE_STRENGTH;
}

// Luz concentrada en el fondo: 1 / |det(I + cH)|, cada canal con c algo distinto (dispersión)
vec3 causticFocus(vec3 h, float c) {
    vec3 cc = c * vec3(0.88, 1.0, 1.13);
    vec3 det = (1.0 + cc * h.x) * (1.0 + cc * h.y) - cc * cc * h.z * h.z;
    return inversesqrt(det * det + 0.0144);
}

// Factor de color de lo sumergido. Rejilla de 16 por bloque, 2x2 muestras por texel, proyectado según el sol
vec3 waterCaustics(vec3 pos, vec3 n, float waterDepth, float skyL, float strength) {
    if (!overworldSky()) return vec3(1.0);
    vec3 L = lightDirWorld();
    float d = max(waterDepth, 0.0) / max(L.y, 0.25);
    float ls = luminance(celestialLightColor());
    float share = ls / (ls + luminance(ambientSkyLight()) + 0.02);
    float fade = strength * share * mainLightFade(skyL) * saturate(dot(n, L) * 2.0)
               * smoothstep(0.05, 0.4, d) * exp(-d * 0.08);
    if (fade < 0.01) return vec3(1.0);
    vec3 wl = (floor((pos + cameraPositionFract) * 16.0) + 0.5) / 16.0;   // relativo al bloque de la cámara
    fade *= luminance(getShadow(wl - cameraPositionFract, n));
    if (fade < 0.01) return vec3(1.0);
    vec3 w = wl + vec3(cameraPositionInt & ivec3(1023));
    vec2 q = w.xz - L.xz * (w.y / max(L.y, 0.25));
    float t = frameTimeCounter;
    // poco fondo: curvas más anchas
    float c = 8.0 * (0.5 + 0.5 * smoothstep(0.3, 2.0, d));
    vec3 I = vec3(0.0);
    for (int k = 0; k < 4; k++) {
        vec2 o = (vec2(k & 1, k >> 1) - 0.5) * (0.5 / 16.0);
        I += causticFocus(causticHessian(q + o, t), c);
    }
    I *= 0.25;
    // variación lenta de intensidad
    float groups = 0.9 + 0.25 * sin(dot(q, vec2(0.21, 0.13)) + t * 0.11) * sin(dot(q, vec2(-0.17, 0.19)) - t * 0.07);
    return 1.0 + fade * CAUSTICS_STRENGTH * groups * (0.65 * I - 0.65);
}

#endif
