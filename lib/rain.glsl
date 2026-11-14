#ifndef MRPIXEL_RAIN
#define MRPIXEL_RAIN

// Requiere common.glsl. Se evalúa en el centro de la celda pixelada.

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Charcos: metaballs en celdas de 2.5 bloques
float puddleField(vec2 xz) {
    vec2 p = xz / 2.5;
    vec2 b = floor(p);
    float f = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 c = b + vec2(float(i), float(j));
            vec2 center = c + 0.25 + 0.5 * vec2(hash12(c * 1.13 + 3.7), hash12(c * 2.71 + 9.1));
            float r = 0.42 + 0.33 * hash12(c * 4.19 + 1.3);
            vec2 d = (p - center) / r;
            f += max(1.0 - dot(d, d), 0.0);
        }
    }
    return f;
}

// coverage: fracción del suelo expuesto con charco (1 = todo)
bool isPuddle(vec2 xz, float coverage) {
    if (coverage >= 0.995) return true;
    return puddleField(xz) >= mix(1.0, 0.0, coverage);
}

// 1 = le cae la lluvia (luz de cielo 15 y, con vóxeles, columna libre)
float rainExposure(vec3 pos, float skyLight) {
    float e = smoothstep(0.955, 0.985, skyLight);
    if (e <= 0.0) return 0.0;
#ifdef VOXEL_READ
    ivec3 v = playerToVoxel(pos - vec3(0.0, 0.02, 0.0)) + ivec3(0, 1, 0);
    if (all(greaterThanEqual(v, ivec3(0))) && v.x < VOXEL_SIZE && v.z < VOXEL_SIZE) {
        for (int i = 0; i < 48; i++) {
            ivec3 q = v + ivec3(0, i, 0);
            if (q.y >= VOXEL_SIZE) break;
            if (voxelBlocksRain(voxelData(q))) return 0.0;
        }
    }
#endif
    return e;
}

// Anillos de gotas en celdas de medio bloque. p: XZ de mundo; slope: pendiente para la normal.
float rainRipples(vec2 p, float t, float amount, out vec2 slope) {
    slope = vec2(0.0);
    float ring = 0.0;
    vec2 base = floor(p * 2.0);
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 c = base + vec2(float(i), float(j));
            float h = hash12(c * 1.37 + 0.71);
            float tt = t * (0.8 + 0.5 * h) + h * 17.0;
            float cycle = floor(tt);
            if (hash12(c * 0.53 + cycle * 2.71) > amount) continue;
            float ph = fract(tt);
            vec2 center = (c + vec2(hash12(c + cycle * 3.17), hash12(c * 1.91 + cycle * 1.3))) * 0.5;
            vec2 d = p - center;
            float r = length(d);
            float k = (r - ph * 0.42) / 0.045;
            float fade = (1.0 - ph) * (1.0 - ph);
            float g = exp(-k * k) * fade;
            ring += g;
            if (r > 1e-4) slope += (d / r) * (-2.0 * k) * g * 0.06;
        }
    }
    return saturate(ring);
}

#endif
