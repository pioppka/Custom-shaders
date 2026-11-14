#ifndef MRPIXEL_GROUNDFOG
#define MRPIXEL_GROUNDFOG

// Niebla de suelo del deep dark: (2 x GROUND_FOG_DISTANCE) x 64 x (2 x GROUND_FOG_DISTANCE) bloques, celdas de 1/2
// bloque (1/4 en vertical). La rellena shadowcomp3. Requiere: settings, uniforms, common

const ivec3 GFOG_P = ivec3(2, 4, 2);                      // celdas por bloque (x, y, z)
// tiene que coincidir con las imágenes de shaders.properties
const ivec3 GFOG_BLOCKS = ivec3(GROUND_FOG_DISTANCE * 2, 64, GROUND_FOG_DISTANCE * 2);
const ivec3 GFOG_HALF = GFOG_BLOCKS / 2;
const ivec3 GFOG_CELLS = GFOG_BLOCKS * GFOG_P;
const float GFOG_DIST = float(GROUND_FOG_DISTANCE) - 4.0;   // alcance (bloques)

// bloque del volumen donde cae un punto (espacio jugador)
ivec3 gfogBlock(vec3 playerPos) { return ivec3(floor(playerPos + cameraPositionFract)) + GFOG_HALF; }
bool gfogInBlocks(ivec3 b) { return all(greaterThanEqual(b, ivec3(0))) && all(lessThan(b, GFOG_BLOCKS)); }
bool gfogInCells(ivec3 c) { return all(greaterThanEqual(c, ivec3(0))) && all(lessThan(c, GFOG_CELLS)); }

// Ruido de valor 3D (0-1), suave
float gfogNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x);
    float b = mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x);
    float c = mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x);
    float d = mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

// Densidad objetivo en wp a h bloques sobre el suelo
float gfogTarget(vec3 wp, float h) {
    float t = frameTimeCounter * GROUND_FOG_SPEED;
    vec3 p = wp * vec3(0.17, 0.36, 0.17);
    vec3 warp = vec3(gfogNoise(p * 0.45 + vec3(t * 0.05, 0.0, 3.1)),
                     gfogNoise(p * 0.45 + vec3(7.3, t * 0.04, 1.9)),
                     gfogNoise(p * 0.45 + vec3(2.6, 5.4, t * 0.06))) - 0.5;
    vec3 q = p + warp * 1.5 + vec3(t * 0.12, -t * 0.02, t * 0.08);
    float n = gfogNoise(q) * 0.64
            + gfogNoise(q * 2.1 + vec3(-t * 0.21, t * 0.07, t * 0.17)) * 0.28
            + gfogNoise(q * 4.3 + vec3(t * 0.33, -t * 0.12, -t * 0.27)) * 0.08;
    float cover = smoothstep(0.30, 0.74, n);
    float hs = GROUND_FOG_HEIGHT * (0.35 + 0.65 * cover);
    float fall = exp(-h / (hs * 0.55));
    float dome = smoothstep(0.0, 0.7, 1.0 - h / hs + (n - 0.5) * 0.5);
    return (0.06 + 1.34 * cover) * fall * dome;
}

#endif
