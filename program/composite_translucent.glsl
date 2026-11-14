// Composite: capa translúcida con refracción pixelada, absorción y espuma de orilla

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

out vec2 uv;

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = ftransform();
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

#ifdef FLOODFILL
    #define VOXEL_READ
#endif
#if defined WATER_FOAM && !defined FLOODFILL
    #define SHORE_MAP
uniform usampler3D shoreSampler;
#endif
#include "/lib/sky.glsl"
#include "/lib/voxel.glsl"
#ifdef WATER_CAUSTICS
    #define SHADOW_SAMPLING
#include "/lib/shadows.glsl"
#include "/lib/caustics.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
#ifdef WATER_CAUSTICS
uniform sampler2D colortex4;
#endif

#include "/lib/translucent.glsl"

in vec2 uv;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

#ifdef IMPACT_ON
#include "/lib/state.glsl"

// Umbral del frame de impacto (IMPACT_THRESHOLD del brillo medio, 16x9 muestras) y si se invierte
void impactThreshold(out float threshold, out float invert) {
    float lum[144];
    float avg = 0.0;
    for (int i = 0; i < 144; i++) {
        lum[i] = luminance(texelFetch(colortex0, ivec2((vec2(i % 16, i / 16) + 0.5) / vec2(16.0, 9.0) * viewSize()), 0).rgb);
        avg += lum[i] / 144.0;
    }
    threshold = avg * IMPACT_THRESHOLD;
    float above = 0.0;
    for (int i = 0; i < 144; i++) above += step(threshold, lum[i]);
    invert = above < 72.0 ? 1.0 : 0.0;
}

#ifdef IMPACT_FRAMES
uniform float frameTime;
#endif

// Frame de impacto (mrState.impactState, juego del frame anterior -> este): 0 última explosión vista, 1 inicio, 2-4
// posición, 5 umbral, 6 invertido, 7 muestras recientes. Tiempos +1 (0 = nunca).
void updateImpact() {
    int prev = (frameCounter & 1) == 0 ? 8 : 0;
    int cur = 8 - prev;
    float state[8];
    for (int i = 0; i < 8; i++) state[i] = mrState.impactState[prev + i];
#ifdef IMPACT_FRAMES
    int n = mrState.impactSeen[0];
    float near = float(10000 - mrState.impactSeen[4]) / 100.0;
    float now = frameTimeCounter + 1.0;
    // explosión: blanco puro y casi nada casi blanco
    bool seen = n >= 4 && mrState.impactSeen[5] * 8 <= n && near < float(IMPACT_RANGE);
    if (seen) {
        bool fresh = now - state[0] > 0.6 || now < state[0] || float(n) > state[7] * 3.0 + 16.0;
        bool rested = now - state[1] > IMPACT_DURATION + IMPACT_COOLDOWN || now < state[1];
        if (fresh && rested) {
            state[1] = now;
            vec3 at = vec3(mrState.impactSeen[1], mrState.impactSeen[2], mrState.impactSeen[3]) / (4.0 * float(n))
                    + cameraPosition;
            state[2] = at.x;
            state[3] = at.y;
            state[4] = at.z;
            impactThreshold(state[5], state[6]);
        }
        state[0] = now;
    }
    state[7] = mix(state[7], seen ? float(n) : 0.0, 1.0 - exp(-2.0 * frameTime));
    for (int i = 0; i < 8; i++) mrState.impactSeen[i] = 0;
#endif
#if IMPACT_DEBUG > 0
    impactThreshold(state[5], state[6]);
#endif
    for (int i = 0; i < 8; i++) mrState.impactState[cur + i] = state[i];
}
#endif

ivec2 clampPx(vec2 p) {
    return clamp(ivec2(p), ivec2(0), ivec2(viewSize()) - 1);
}

// Distancia horizontal (bloques) a la orilla; -1 sin datos del agua
#if defined VOXEL_READ || defined SHORE_MAP
const int SHORE_R = int(ceil(0.80 * SHORE_FOAM_WIDTH));
const uint SHORE_WATER = 1u;
const uint SHORE_GEOM = 2u;
const uint SHORE_SOLID = 4u;
const uint SHORE_OUT = 0x100u;

// b: bloque relativo al de la cámara (vóxeles o mapa de la orilla)
uint shoreBits(ivec3 b) {
#ifdef VOXEL_READ
    ivec3 v = b + VOXEL_HALF;
    if (!inVoxelVolume(v)) return SHORE_OUT;
    uint d = voxelData(v);
    return ((d & VOX_WATER) != 0u ? SHORE_WATER : 0u) | ((d & (VOX_GEOMETRY | VOX_SOLID)) != 0u ? SHORE_GEOM : 0u)
         | ((d & VOX_SOLID) != 0u ? SHORE_SOLID : 0u);
#else
    if (abs(b.x) > 30 || abs(b.y) > 14 || abs(b.z) > 30) return SHORE_OUT;
    return texelFetch(shoreSampler, (b + cameraPositionInt) & ivec3(63, 31, 63), 0).r;
#endif
}

float shoreDistance(vec3 surfPlayer) {
    // poco margen bajo la superficie (cascadas)
    vec3 w = surfPlayer - vec3(0.0, 0.01, 0.0);
    ivec3 b = ivec3(floor(w + cameraPositionFract));
    uint here = shoreBits(b);
    // punta del agua corrida
    if (here != SHORE_OUT && (here & SHORE_WATER) == 0u) here = shoreBits(++b);
    if (here == SHORE_OUT || (here & SHORE_WATER) == 0u) return -1.0;
    vec2 f = fract(w.xz + cameraPositionFract.xz);
    float d = 9.0;
    for (int dx = -SHORE_R; dx <= SHORE_R; dx++) {
        for (int dz = -SHORE_R; dz <= SHORE_R; dz++) {
            if (dx == 0 && dz == 0) continue;
            uint nd = shoreBits(b + ivec3(dx, 0, dz));
            if (nd == SHORE_OUT) continue;
            if ((nd & SHORE_SOLID) == 0u) {
                if ((nd & SHORE_WATER) != 0u) continue;
                uint bd = shoreBits(b + ivec3(dx, -1, dz));
                if (bd == SHORE_OUT || (bd & SHORE_GEOM) == 0u || (bd & SHORE_WATER) != 0u) continue;
            }
            vec2 lo = vec2(float(dx), float(dz));
            d = min(d, length(f - clamp(f, lo, lo + 1.0)));
        }
    }
    return d;
}
#endif

// Fase de la ola a lo largo de la orilla
float foamPhase(vec2 p) {
    return 0.18 * sin(p.x * 0.31 + 0.9 * sin(p.y * 0.23)) + 0.14 * sin(p.y * 0.27 - p.x * 0.11);
}

// Espuma según la distancia a la orilla (en anchos de espuma). Devuelve color y cobertura
vec4 cartoonFoam(float dd, vec2 cellW) {
    float wp = fract(frameTimeCounter * 0.24 + foamPhase(cellW));   // ~4 s
    float swell = cos(wp * 6.2832);
    if (dd < 0.10 + 0.03 * swell) return vec4(0.97, 0.99, 1.00, 0.95);
    if (dd < 0.26 + 0.05 * swell) return vec4(0.62, 0.86, 1.00, 0.70);
    float lineD = mix(0.30, 0.74, 1.0 - (1.0 - wp) * (1.0 - wp));
    // al menos ~1 píxel de grueso
    float halfW = max(0.035, 0.6 / (FOAM_PIXELS * SHORE_FOAM_WIDTH));
    float a = 0.75 * smoothstep(0.02, 0.14, wp) * (1.0 - smoothstep(0.15, 0.95, wp));
    if (abs(dd - lineD) < halfW) return vec4(0.82, 0.94, 1.00, a);
    return vec4(0.0);
}

// ¿Hay algo en q delante del punto de la superficie?
bool refractBlocked(ivec2 q, vec3 expectedPlayer) {
    float expectedDist = -playerToView(expectedPlayer).z;
    return linearDepth(texelFetch(depthtex0, q, 0).r) < expectedDist - 0.15;
}

// Centro de la celda tapado: prueba otros cuatro puntos de la celda
ivec2 cellFallback(ivec2 px, vec3 cell, int axis, float P) {
    vec3 u = vec3(0.0);
    vec3 v = vec3(0.0);
    u[(axis + 1) % 3] = 0.25 / P;
    v[(axis + 2) % 3] = 0.25 / P;
    for (int k = 0; k < 4; k++) {
        vec3 alt = cell + u * ((k & 1) == 0 ? -1.0 : 1.0) + v * (k < 2 ? -1.0 : 1.0);
        ivec2 q = clampPx(viewToScreen(playerToView(alt)).xy * viewSize());
        if (!refractBlocked(q, alt)) return q;
    }
    return px;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
#ifdef IMPACT_ON
    if (px == ivec2(0)) updateImpact();
#endif
    vec2 res = viewSize();
    vec3 col = texelFetch(colortex0, px, 0).rgb;
    vec4 trans = texelFetch(colortex5, px, 0);
    vec4 tdat = texelFetch(colortex6, px, 0);
    float d0 = texelFetch(depthtex0, px, 0).r;

#ifdef WATER_CAUSTICS
    // cámara bajo el agua: el agua de encima sale de la luz de cielo
    if (isEyeInWater == 1 && tdat.w >= 1.0 && d0 < SKY_DEPTH) {
        vec4 g = texelFetch(colortex1, px, 0);
        int m = decodeMaterial(g.b);
        if (m != MAT_HAND && m != MAT_CLOUD && m != MAT_NONE) {
            float lb = texelFetch(colortex4, px, 0).b;
            col *= waterCaustics(viewToPlayer(screenToView(uv, d0)), decodeNormal(g.rg), (1.0 - lb) * 15.0, lb, 1.0);
        }
    }
#endif

    // también superficie sin color (cristal transparente)
    if (trans.a > 0.0005 || tdat.w < 1.0) {
        bool hasSurface = tdat.w < 1.0;
        // se omite si algo dibujado después quedó delante
        int frontMat = decodeMaterial(texelFetch(colortex1, px, 0).b);
        bool laterOpaque = frontMat == MAT_ENTITY || frontMat == MAT_HAND || frontMat == MAT_CLOUD
                        || frontMat == MAT_TEXT || frontMat == MAT_BLOCKENTITY;
        bool front = hasSurface ? (!laterOpaque || tdat.w <= d0 + 1e-6) : frontMat != MAT_HAND;

        if (front) {
            vec3 bg = col;
            vec3 foam = vec3(0.0);
            float foamMask = 0.0;

            if (hasSurface) {
                float surfDepth;
                vec3 Nw;
                int mat;
                float skyL;
                frontTranslucent(px, uv, tdat, d0, laterOpaque, surfDepth, Nw, mat, skyL);

                if (mat != MAT_PORTAL) {
                    vec3 surf = viewToPlayer(screenToView(uv, surfDepth));
                    vec3 wp = surf + cameraPositionFract;

                    vec3 an = abs(Nw);
                    int axis = (an.x > an.y && an.x > an.z) ? 0 : (an.y > an.z ? 1 : 2);
                    vec3 axisN = vec3(0.0);
                    axisN[axis] = Nw[axis] >= 0.0 ? 1.0 : -1.0;

                    float P = float(REFRACTION_PIXELS);
                    vec3 snapped = (floor(wp * P) + 0.5) / P;
                    snapped[axis] = wp[axis];
                    vec3 snapPlayer = snapped - cameraPositionFract;
                    // espuma en su rejilla
                    vec3 snappedF = (floor(wp * FOAM_PIXELS) + 0.5) / FOAM_PIXELS;
                    snappedF[axis] = wp[axis];
                    vec3 snapPlayerF = snappedF - cameraPositionFract;
                    ivec2 rpx = px;
#ifdef REFRACTION
                    vec3 pert = Nw - axisN;
                    vec3 target = snapPlayer + pert * 0.6 * REFRACTION_STRENGTH;
                    rpx = clampPx(viewToScreen(playerToView(target)).xy * res);
                    if (refractBlocked(rpx, target)) {
                        rpx = clampPx(viewToScreen(playerToView(snapPlayer)).xy * res);
                        if (refractBlocked(rpx, snapPlayer)) rpx = cellFallback(px, snapPlayer, axis, P);
                    }
                    bg = texelFetch(colortex0, rpx, 0).rgb;
#endif

                    if (mat == MAT_WATER && isEyeInWater == 0) {
                        float bd = texelFetch(depthtex1, rpx, 0).r;
                        vec3 bp = viewToPlayer(screenToView((vec2(rpx) + 0.5) / res, bd));
                        float dist = bd >= SKY_DEPTH ? 64.0 : length(bp - surf);
#ifdef WATER_CAUSTICS
                        // se apagan con celdas de refracción gruesas
                        if (bd < SKY_DEPTH) {
    #ifdef REFRACTION
                            float cs = smoothstep(3.0, 10.0, P);
    #else
                            float cs = 1.0;
    #endif
                            bg *= waterCaustics(bp, decodeNormal(texelFetch(colortex1, rpx, 0).rg), surf.y - bp.y,
                                                texelFetch(colortex4, rpx, 0).b, cs);
                        }
#endif
                        bg *= exp(-dist * vec3(0.32, 0.11, 0.07));   // absorción

#ifdef WATER_FOAM
                        vec3 cellW = snappedF + vec3(cameraPositionInt & ivec3(1023));
                        // profundidad en el centro de la celda
                        ivec2 cpx = clampPx(viewToScreen(playerToView(snapPlayerF)).xy * res);
                        float cd = texelFetch(depthtex1, cpx, 0).r;
                        vec3 cbp = viewToPlayer(screenToView((vec2(cpx) + 0.5) / res, cd));
                        if (cd < SKY_DEPTH && length(cbp) < length(snapPlayerF) - 0.02) {
                            cd = texelFetch(depthtex1, px, 0).r;
                            cbp = viewToPlayer(screenToView((vec2(px) + 0.5) / res, cd));
                        }
                        float vdepth = cd >= SKY_DEPTH ? 64.0 : snapPlayerF.y - cbp.y;
                        // distancia a la orilla: vóxeles o profundidad
                        float dShore = vdepth * 1.6;
#if defined VOXEL_READ || defined SHORE_MAP
                        float sd = shoreDistance(snapPlayerF);
                        if (sd >= 0.0) dShore = sd;
#endif
                        vec4 cf = cartoonFoam(dShore / SHORE_FOAM_WIDTH, cellW.xz);
                        foamMask = cf.a * step(0.5, Nw.y);
                        vec3 foamLight = celestialLightColor() * 0.7 * skyL + ambientSkyLight() * (0.4 + skyL) + vec3(0.05);
#ifdef FLOODFILL
                        // luces de bloque cercanas
                        vec3 ffL, ffD;
                        float ffW = sampleFloodfill(snapPlayerF, vec3(0.0, 1.0, 0.0), ffL, ffD);
                        foamLight += limitBlockLight(ffL * (ffW * FLOODFILL_BRIGHTNESS * 1.3 * BLOCKLIGHT_BRIGHTNESS), foamLight, skyL);
#endif
                        foam = cf.rgb * foamLight;
#endif
                    }
                }
            }

            col = mix(trans.rgb + bg * (1.0 - trans.a), foam, foamMask);
        }
    }

    outColor = vec4(col, 1.0);
}

#endif
