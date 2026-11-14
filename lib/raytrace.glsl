#ifndef MRPIXEL_RAYTRACE
#define MRPIXEL_RAYTRACE

// Requiere: colortex0 y depthtex0 declarados; common.glsl

#ifdef SKY_REFLECTIONS
uniform float cloudHeight;
#endif

// ¿El punto del rayo queda detrás de lo que se ve?
bool rayBehind(vec3 sp, vec2 res) {
    float d = texelFetch(depthtex0, ivec2(sp.xy * res), 0).r;
    return d < SKY_DEPTH && sp.z > d;
}

// Reflejos en pantalla. Devuelve confianza (0 = sin impacto). Impacto: el paso en que el rayo pasa detrás de la
// superficie; refinado después.
float traceScreen(vec3 originPlayer, vec3 dirPlayer, int maxSteps, out vec3 hitColor) {
    hitColor = vec3(0.0);
    vec3 vo = playerToView(originPlayer);
    vec3 vd = normalize(mat3(gbufferModelView) * dirPlayer);

    float maxLen = far * 1.5;
#ifdef SKY_REFLECTIONS
    // hasta la capa de nubes
    if (dirPlayer.y > 0.02) {
        maxLen = max(maxLen, min((cloudHeight + 4.0 - cameraPosition.y - originPlayer.y) / dirPlayer.y, far * 3.5));
    }
#endif
    if (vd.z > 0.0) maxLen = min(maxLen, (-near * 2.0 - vo.z) / vd.z);
    if (maxLen <= 0.05) return 0.0;

    vec3 ve = vo + vd * maxLen;
    vec3 so = viewToScreen(vo);
    vec3 se = viewToScreen(ve);
    vec2 res = viewSize();

    vec2 dir = se.xy - so.xy;
    float tEnd = 1.0;
    if (dir.x > 1e-6) tEnd = min(tEnd, (1.0 - so.x) / dir.x);
    else if (dir.x < -1e-6) tEnd = min(tEnd, -so.x / dir.x);
    if (dir.y > 1e-6) tEnd = min(tEnd, (1.0 - so.y) / dir.y);
    else if (dir.y < -1e-6) tEnd = min(tEnd, -so.y / dir.y);
    tEnd *= 0.999;
    if (tEnd <= 0.0) return 0.0;

    vec2 dpx = dir * res * tEnd;
    float pxLen = max(abs(dpx.x), abs(dpx.y));
    int steps = int(clamp(pxLen / 4.0, 12.0, float(maxSteps)));

    float invZo = 1.0 / vo.z;
    float invZe = 1.0 / ve.z;
    float tPrev = 0.0;
    bool wasBehind = true;   // los primeros pasos leen el píxel del origen: sólo cuenta tras verse delante

    for (int i = 1; i <= 64; i++) {
        if (i > steps) break;
        float u = float(i) / float(steps);
        float t = u * u * tEnd;
        bool behind = rayBehind(mix(so, se, t), res);
        if (behind && !wasBehind) {
            float a = tPrev;
            float b = t;
            for (int j = 0; j < 6; j++) {
                float m = (a + b) * 0.5;
                if (rayBehind(mix(so, se, m), res)) b = m; else a = m;
            }
            vec2 huv = mix(so.xy, se.xy, b);
            float za = 1.0 / mix(invZo, invZe, a);
            float zb = 1.0 / mix(invZo, invZe, b);
            float sceneZ = -linearDepth(texelFetch(depthtex0, ivec2(huv * res), 0).r);
            if (sceneZ - zb < 0.35 + abs(zb) * 0.035 + abs(zb - za)) {
                hitColor = texelFetch(colortex0, ivec2(huv * res), 0).rgb;
                vec2 edge = abs(huv * 2.0 - 1.0);
                return 1.0 - smoothstep(0.85, 1.0, max(edge.x, edge.y));
            }
        }
        wasBehind = behind;
        tPrev = t;
    }
    return 0.0;
}

#ifdef VOXEL_READ
uniform sampler2D blockAtlasTex;   // atlas de bloques
#if defined PBR_SPECULAR && defined PBR_EMISSIVE
    #define RT_PBR_EMISSION
uniform sampler2D blockAtlasSpecTex;   // mapa especular (1x1 sin PBR)
#endif

// UV de un punto de la cara (h: 0..1 en el bloque)
vec2 faceUV(int face, vec3 h) {
    if (face == 0) return h.xz;
    if (face == 1) return vec2(h.x, 1.0 - h.z);
    if (face == 2) return vec2(1.0 - h.x, 1.0 - h.y);
    if (face == 3) return vec2(h.x, 1.0 - h.y);
    if (face == 4) return vec2(1.0 - h.z, 1.0 - h.y);
    return vec2(h.z, 1.0 - h.y);
}

// Texel del atlas con el mipmap según footprint (bloques por píxel)
vec4 spriteTexel(uint w, vec2 uv, float footprint, out int lod) {
    ivec2 minT = ivec2(int(w & 8191u), int((w >> 13u) & 8191u));
    int log2Size = int((w >> 26u) & 15u);
    float size = float(1 << log2Size);
    lod = clamp(int(floor(log2(max(size * footprint, 1.0)))), 0, min(textureQueryLevels(blockAtlasTex) - 1, log2Size));
    ivec2 tc = (minT + ivec2(min(uv * size, vec2(size - 0.5)))) >> lod;
    return texelFetch(blockAtlasTex, tc, lod);
}

// Emisión labPBR del texel, sólo de cerca
float spriteEmission(uint w, vec2 uv, int lod) {
#ifdef RT_PBR_EMISSION
    if (lod > 1 || textureSize(blockAtlasSpecTex, 0) != textureSize(blockAtlasTex, 0)) return 0.0;
    ivec2 minT = ivec2(int(w & 8191u), int((w >> 13u) & 8191u));
    float size = float(1 << int((w >> 26u) & 15u));
    float a = texelFetch(blockAtlasSpecTex, minT + ivec2(min(uv * size, vec2(size - 0.5))), 0).a;
    return a < 0.999 ? a : 0.0;
#else
    return 0.0;
#endif
}

vec3 voxelTint(ivec3 cell) {
    uint tw = voxelSlot(cell, SLOT_TINT);
    return tw != 0u ? unpackUnorm4x8(tw).rgb : vec3(1.0);
}

// Texel de una cara con su tinte (si falta, otra cara del bloque) y la capa con huecos encima. cutout: alfa de cerca.
// pbrEm: emisión.
bool voxelFaceTexel(ivec3 cell, int face, vec3 h, float footprint, bool cutout, bool glowLayer, out vec4 texel, out float pbrEm) {
    texel = vec4(0.0);
    pbrEm = 0.0;
    uint w = voxelSlot(cell, SLOT_FACE + face);
    for (int k = 0; k < 6 && w == 0u; k++) {
        int f = face >= 2 ? int[6](2, 3, 4, 5, 1, 0)[k] : (face == 0 ? int[6](1, 2, 3, 4, 5, 0)[k] : int[6](0, 2, 3, 4, 5, 1)[k]);
        w = voxelSlot(cell, SLOT_FACE + f);
    }
    if (w == 0u) return false;
    vec2 uv = faceUV(face, h);
    int lod;
    texel = spriteTexel(w, uv, footprint, lod);
    pbrEm = spriteEmission(w, uv, lod);
    if (cutout) texel.a = lod < 2 ? texel.a : 1.0;
    vec3 tint = voxelTint(cell);
    if ((w & (1u << 30u)) != 0u) texel.rgb *= tint;
    if (face >= 2 || glowLayer) {
        uint ow = voxelSlot(cell, SLOT_OVERLAY);
        if (ow != 0u && (ow & 0x3FFFFFFFu) != (w & 0x3FFFFFFFu)) {
            int olod;
            vec4 ov = spriteTexel(ow, uv, footprint, olod);
            if (ov.a > 0.5) {
                texel.rgb = ov.rgb * ((ow & (1u << 30u)) != 0u ? tint : vec3(1.0));
                if (glowLayer) pbrEm = 1.0;
            }
        }
    }
    return true;
}

// Planta cross: dos planos diagonales. Sólo de cerca.
bool hitPlant(ivec3 cell, vec3 entry, vec3 dir, float tExit, float footprint, out float tHit, out vec3 n, out vec4 color) {
    tHit = 1e9;
    n = vec3(0.0, 1.0, 0.0);
    color = vec4(0.0);
    uint w = 0u;
    for (int k = 0; k < 6 && w == 0u; k++) w = voxelSlot(cell, SLOT_FACE + k);
    if (w == 0u) return false;
    if (float(1 << int((w >> 26u) & 15u)) * footprint > 2.0) return false;
    for (int k = 0; k < 2; k++) {
        float sgn = k == 0 ? 1.0 : -1.0;                 // plano: (x - 0.5) = sgn * (z - 0.5)
        float denom = dir.x - sgn * dir.z;
        if (abs(denom) < 1e-6) continue;
        float t = (sgn * (entry.z - 0.5) - (entry.x - 0.5)) / denom;
        if (t < 0.0 || t > tExit || t >= tHit) continue;
        vec3 h = entry + dir * t;
        float u = (h.x - 0.05) / 0.90;
        if (u < 0.0 || u > 1.0 || h.y < 0.0 || h.y > 1.0) continue;
        int lod;
        vec4 c = spriteTexel(w, vec2(u, 1.0 - h.y), footprint, lod);
        if (c.a < 0.5) continue;
        tHit = t;
        color = c;
        vec3 nn = normalize(vec3(1.0, 0.0, -sgn));
        n = dot(nn, dir) > 0.0 ? -nn : nn;
    }
    if (tHit > 1e8) return false;
    if ((w & (1u << 30u)) != 0u) color.rgb *= voxelTint(cell);
    return true;
}

// Texturas de composite.csh (64x64): 0-3 amatista, 4-7 antorchas, 8 arbusto de luciérnagas, 9 sus luciérnagas
uniform sampler2D extraTexSampler;

vec4 extraTexel(int slot, vec2 uv) {
    return texelFetch(extraTexSampler, ivec2(slot * 64, 0) + ivec2(clamp(uv, 0.0, 0.9999) * 64.0), 0);
}

// Arbusto de luciérnagas: cross con las dos capas
bool hitFireflyBush(vec3 entry, vec3 dir, float tExit, out float tHit, out vec3 n, out vec3 color, out float glow) {
    tHit = 1e9;
    n = vec3(0.0, 1.0, 0.0);
    color = vec3(0.0);
    glow = 0.0;
    for (int k = 0; k < 2; k++) {
        float sgn = k == 0 ? 1.0 : -1.0;                 // plano: (x - 0.5) = sgn * (z - 0.5)
        float denom = dir.x - sgn * dir.z;
        if (abs(denom) < 1e-6) continue;
        float t = (sgn * (entry.z - 0.5) - (entry.x - 0.5)) / denom;
        if (t < 0.0 || t > tExit || t >= tHit) continue;
        vec3 h = entry + dir * t;
        float u = (h.x - 0.05) / 0.90;
        if (u < 0.0 || u > 1.0 || h.y < 0.0 || h.y > 1.0) continue;
        vec2 uv = vec2(u, 1.0 - h.y);
        vec4 g = extraTexel(9, uv);
        vec4 c = extraTexel(8, uv);
        if (g.a < 0.5 && c.a < 0.5) continue;
        tHit = t;
        glow = g.a >= 0.5 ? 1.0 : 0.0;
        color = glow > 0.0 ? g.rgb : c.rgb;
        vec3 nn = normalize(vec3(1.0, 0.0, -sgn));
        n = dot(nn, dir) > 0.0 ? -nn : nn;
    }
    return tHit < 1e8;
}

// Amatista: cross girado según la cara. entry: entrada en el vóxel, tExit: distancia a la salida
bool hitAmethyst(int id, vec3 entry, vec3 dir, float tExit, out float tHit, out vec3 n, out vec3 color) {
    int size = (id - 80) / 6;
    int face = (id - 80) % 6;
    int ua = face < 2 ? 1 : (face < 4 ? 2 : 0);
    bool grows = face == 0 || face == 3 || face == 4;
    int pa = ua == 0 ? 1 : 0;
    int qa = ua == 2 ? 1 : 2;
    tHit = 1e9;
    n = vec3(0.0, 1.0, 0.0);
    color = vec3(0.0);
    for (int k = 0; k < 2; k++) {
        float sgn = k == 0 ? 1.0 : -1.0;                 // plano: (p - 0.5) = sgn * (q - 0.5)
        float denom = dir[pa] - sgn * dir[qa];
        if (abs(denom) < 1e-6) continue;
        float t = (sgn * (entry[qa] - 0.5) - (entry[pa] - 0.5)) / denom;
        if (t < 0.0 || t > tExit || t >= tHit) continue;
        vec3 h = entry + dir * t;
        float u = (h[pa] - 0.05) / 0.90;
        if (u < 0.0 || u > 1.0 || h[ua] < 0.0 || h[ua] > 1.0) continue;
        float v = grows ? 1.0 - h[ua] : h[ua];
        vec4 c = extraTexel(size, vec2(u, v));
        if (c.a < 0.5) continue;
        tHit = t;
        color = c.rgb;
        vec3 nn = vec3(0.0);
        nn[pa] = 1.0;
        nn[qa] = -sgn;
        n = normalize(nn) * (dot(nn, dir) > 0.0 ? -1.0 : 1.0);
    }
    return tHit < 1e8;
}

// Antorcha con el modelo de vanilla (template_torch y template_torch_wall). glow: llama
bool hitTorch(int id, vec3 entry, vec3 dir, float tExit, out float tHit, out vec3 n, out vec3 color, out float glow) {
    int type = (id - 110) / 5;
    int place = (id - 110) % 5;
    tHit = 0.0;
    n = vec3(0.0, 1.0, 0.0);
    color = vec3(0.0);
    glow = 0.0;
    // al espacio del modelo
    vec3 o = entry * 16.0 - 8.0;
    vec3 dd = dir * 16.0;
    if (place == 2)      { o = vec3(o.z, o.y, -o.x);  dd = vec3(dd.z, dd.y, -dd.x); }
    else if (place == 3) { o = vec3(-o.x, o.y, -o.z); dd = vec3(-dd.x, dd.y, -dd.z); }
    else if (place == 4) { o = vec3(-o.z, o.y, o.x);  dd = vec3(-dd.z, dd.y, dd.x); }
    o += 8.0;
    vec3 bmin = vec3(7.0, 0.0, 7.0);
    vec3 bmax = vec3(9.0, 10.0, 9.0);
    const float c = 0.92388;   // cos 22.5°
    const float s = 0.38268;   // sin 22.5°
    if (place > 0) {
        // inclinación de la de pared
        vec2 r = o.xy - vec2(0.0, 3.5);
        o.xy = vec2(r.x * c - r.y * s, r.x * s + r.y * c) + vec2(0.0, 3.5);
        dd.xy = vec2(dd.x * c - dd.y * s, dd.x * s + dd.y * c);
        bmin = vec3(-1.0, 3.5, 7.0);
        bmax = vec3(1.0, 13.5, 9.0);
    }
    vec3 inv = 1.0 / vec3(abs(dd.x) < 1e-6 ? 1e-6 : dd.x, abs(dd.y) < 1e-6 ? 1e-6 : dd.y, abs(dd.z) < 1e-6 ? 1e-6 : dd.z);
    vec3 t0 = (bmin - o) * inv;
    vec3 t1 = (bmax - o) * inv;
    vec3 tmn = min(t0, t1);
    vec3 tmx = max(t0, t1);
    float tn = max3(tmn);
    float tf = min3(tmx);
    if (tn > tf || tf < 0.0 || tn > tExit) return false;
    tn = max(tn, 0.0);
    int ax = (tmn.x >= tmn.y && tmn.x >= tmn.z) ? 0 : (tmn.y >= tmn.z ? 1 : 2);
    vec3 hp = o + dd * tn;
    vec3 f = clamp((hp - bmin) / (bmax - bmin), 0.0, 1.0);
    vec2 px;
    if (ax == 1) px = vec2(7.0 + f.x * 2.0, (dd.y < 0.0 ? 6.0 : 13.0) + f.z * 2.0);
    else px = vec2(7.0 + (ax == 0 ? f.z : f.x) * 2.0, 6.0 + (1.0 - f.y) * 10.0);
    vec4 tx = extraTexel(4 + type, px / 16.0);
    if (tx.a < 0.5) return false;
    vec3 nm = vec3(0.0);
    nm[ax] = dd[ax] > 0.0 ? -1.0 : 1.0;
    if (place > 0) nm.xy = vec2(nm.x * c + nm.y * s, -nm.x * s + nm.y * c);
    if (place == 2)      nm = vec3(-nm.z, nm.y, nm.x);
    else if (place == 3) nm = vec3(-nm.x, nm.y, -nm.z);
    else if (place == 4) nm = vec3(nm.z, nm.y, -nm.x);
    tHit = tn;
    n = nm;
    color = tx.rgb;
    // llama: muy clara o sin rojo dominante
    bool coolFlame = tx.g > tx.r * 1.1 || tx.b > tx.r * 1.1;
    glow = coolFlame ? 1.0 : smoothstep(0.64, 0.80, max3(tx.rgb));
    return true;
}

// Caja de una fuente que no es un bloque entero (0..1)
void emitterBox(int id, out vec3 bmin, out vec3 bmax) {
    if (id == 14 || id == 15 || id == 43) {          // portal, lava, magma
        bmin = vec3(0.0);
        bmax = vec3(1.0);
    } else if (id == 62) {                            // fuego
        bmin = vec3(0.05, 0.0, 0.05);
        bmax = vec3(0.95, 0.85, 0.95);
    } else if (id == 56 || id == 60) {               // velas, pepinos de mar
        bmin = vec3(0.38, 0.0, 0.38);
        bmax = vec3(0.62, 0.45, 0.62);
    } else {   // faroles...
        bmin = vec3(0.36, 0.05, 0.36);
        bmax = vec3(0.64, 0.75, 0.64);
    }
}

// DDA por el volumen con la textura de cada cara
bool traceVoxels(vec3 originPlayer, vec3 dir, int maxSteps, out vec3 albedo, out vec3 hitPlayer, out vec3 hitNormal, out float emission) {
    albedo = vec3(0.0);
    hitPlayer = originPlayer;
    hitNormal = vec3(0.0, 1.0, 0.0);
    emission = 0.0;

    vec3 p = originPlayer + cameraPositionFract + float(VOXEL_HALF);
    ivec3 cell = ivec3(floor(p));
    if (!inVoxelVolume(cell)) return false;

    ivec3 stepI = ivec3(sign(dir));
    vec3 invDir = 1.0 / max(abs(dir), vec3(1e-6));
    vec3 fr = p - vec3(cell);
    vec3 tMax = vec3(
        stepI.x > 0 ? (1.0 - fr.x) * invDir.x : (stepI.x < 0 ? fr.x * invDir.x : 1e30),
        stepI.y > 0 ? (1.0 - fr.y) * invDir.y : (stepI.y < 0 ? fr.y * invDir.y : 1e30),
        stepI.z > 0 ? (1.0 - fr.z) * invDir.z : (stepI.z < 0 ? fr.z * invDir.z : 1e30));

    float t = 0.0;
    int axis = 0;
    vec3 safeDir = vec3(stepI.x == 0 ? 1e-6 : dir.x, stepI.y == 0 ? 1e-6 : dir.y, stepI.z == 0 ? 1e-6 : dir.z);
    vec3 invSafe = 1.0 / safeDir;
    float pixelAngle = 2.0 / (gbufferProjection[1][1] * viewHeight);
    float baseDist = length(originPlayer);
    for (int i = 0; i < RT_STEPS; i++) {
        if (i >= maxSteps) break;
        if (tMax.x < tMax.y && tMax.x < tMax.z) {
            cell.x += stepI.x; t = tMax.x; tMax.x += invDir.x; axis = 0;
        } else if (tMax.y < tMax.z) {
            cell.y += stepI.y; t = tMax.y; tMax.y += invDir.y; axis = 1;
        } else {
            cell.z += stepI.z; t = tMax.z; tMax.z += invDir.z; axis = 2;
        }
        if (!inVoxelVolume(cell)) return false;

        uint d = voxelData(cell);
        if ((d & (VOX_SOLID | VOX_LEAVES)) != 0u) {
            vec3 n = vec3(0.0);
            n[axis] = -float(stepI[axis]);
            vec3 h = clamp(p + dir * t - vec3(cell), 0.0, 1.0);
            vec4 texel;
            float pbrEm = 0.0;
            if (voxelFaceTexel(cell, faceIndex(n), h, (baseDist + t) * pixelAngle, (d & VOX_LEAVES) != 0u,
                               (d & VOX_PBRGLOW) != 0u, texel, pbrEm)) {
                if ((d & VOX_LEAVES) != 0u && texel.a < 0.5) continue;
                albedo = saturateColor(toLinear(texel.rgb), ALBEDO_SATURATION);
            } else {
                albedo = vec3(0.30);
            }
            hitPlayer = originPlayer + dir * t;
            hitNormal = n;
            // emisores macizos: sus píxeles claros
            if ((d & VOX_EMITTER) != 0u) emission = 1.6 * float((d >> 16u) & 15u) / 15.0 * smoothstep(0.35, 0.80, max3(albedo));
            emission = max(emission, pbrEm * 1.6 * textureGlowScale(int((d >> 8u) & 255u)));
            return true;
        }
        int vid = int((d >> 8u) & 255u);
        if ((d & VOX_GEOMETRY) != 0u && vid == 9) {
            float th;
            vec3 fn;
            vec3 fc;
            float fg;
            if (16.0 * (baseDist + t) * pixelAngle <= 3.0
                && hitFireflyBush(p + dir * t - vec3(cell), dir, min3(tMax) - t, th, fn, fc, fg)) {
                albedo = saturateColor(toLinear(fc), ALBEDO_SATURATION);
                emission = fg * 2.0;
                hitPlayer = originPlayer + dir * (t + th);
                hitNormal = fn;
                return true;
            }
            continue;
        }
        if ((d & VOX_GEOMETRY) != 0u && (vid == 1 || vid == 2 || vid == 3 || vid == 8)) {
            float th;
            vec3 pn;
            vec4 pc;
            if (hitPlant(cell, p + dir * t - vec3(cell), dir, min3(tMax) - t, (baseDist + t) * pixelAngle, th, pn, pc)) {
                albedo = saturateColor(toLinear(pc.rgb), ALBEDO_SATURATION);
                hitPlayer = originPlayer + dir * (t + th);
                hitNormal = pn;
                return true;
            }
            continue;
        }
        if (idIsAmethyst(vid)) {
            float th;
            vec3 an;
            vec3 ac;
            if (hitAmethyst(vid, p + dir * t - vec3(cell), dir, min3(tMax) - t, th, an, ac)) {
                albedo = saturateColor(toLinear(ac), ALBEDO_SATURATION);
                emission = 1.8 * float((d >> 16u) & 15u) / 5.0;
                hitPlayer = originPlayer + dir * (t + th);
                hitNormal = an;
                return true;
            }
            continue;
        }
        if (idIsTorch(vid)) {
            float th;
            vec3 tn;
            vec3 tc;
            float tg;
            if (hitTorch(vid, p + dir * t - vec3(cell), dir, min3(tMax) - t, th, tn, tc, tg)) {
                albedo = saturateColor(toLinear(tc), ALBEDO_SATURATION);
                emission = tg * 1.6 * float((d >> 16u) & 15u) / 15.0;
                hitPlayer = originPlayer + dir * (t + th);
                hitNormal = tn;
                return true;
            }
            continue;
        }
        // nivel >= 5
        if ((d & VOX_EMITTER) != 0u && ((d >> 16u) & 15u) >= 5u) {
            int id = int((d >> 8u) & 255u);
            vec3 bmin;
            vec3 bmax;
            emitterBox(id, bmin, bmax);
            vec3 t0 = (vec3(cell) + bmin - p) * invSafe;
            vec3 t1 = (vec3(cell) + bmax - p) * invSafe;
            vec3 tmn = min(t0, t1);
            vec3 tmx = max(t0, t1);
            float tn = max3(tmn);
            float tf = min3(tmx);
            if (tn <= tf && tf > 0.0) {
                int ax = (tmn.x >= tmn.y && tmn.x >= tmn.z) ? 0 : (tmn.y >= tmn.z ? 1 : 2);
                vec3 n = vec3(0.0);
                n[ax] = -float(stepI[ax]);
                float level = float((d >> 16u) & 15u) / 15.0;
                albedo = emitterColor(id);
                emission = level * 1.6;
                hitPlayer = originPlayer + dir * max(tn, 0.0);
                hitNormal = n;
                return true;
            }
        }
    }
    return false;
}
#endif

#endif
