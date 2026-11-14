#version 430

// Niebla de suelo (lib/groundfog.glsl): un hilo por columna, de abajo arriba. Se conserva entre frames (desplazada
// con la cámara) y se acerca a la densidad objetivo en ~0.5 s. Sólo en el deep dark (mrState.fogFade).

#include "/lib/settings.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// GROUND_FOG_DISTANCE / 2
#if GROUND_FOG_DISTANCE == 64
const ivec3 workGroups = ivec3(32, 32, 1);
#elif GROUND_FOG_DISTANCE == 32
const ivec3 workGroups = ivec3(16, 16, 1);
#else
const ivec3 workGroups = ivec3(24, 24, 1);
#endif

#if defined FLOODFILL && defined GROUND_FOG

#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#define VOXEL_READ
#include "/lib/voxel.glsl"
#include "/lib/groundfog.glsl"

uniform float frameTime;
uniform int biome;
uniform sampler3D fogSamplerA;
uniform sampler3D fogSamplerB;
uniform usampler3D fogPushSampler;
#include "/lib/state.glsl"

layout(rg16f) writeonly uniform image3D fogImgA;   // r densidad, g luz de arriba
layout(rg16f) writeonly uniform image3D fogImgB;
layout(r32ui) uniform uimage3D fogMaskImg;

// Bloques que tocan las entidades, interpolados
float pushAt(vec3 q) {
    vec3 p = q - 0.5;
    ivec3 b = ivec3(floor(p));
    vec3 f = p - vec3(b);
    float s = 0.0;
    for (int i = 0; i < 8; i++) {
        ivec3 o = ivec3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        ivec3 bb = b + o;
        if (!gfogInBlocks(bb) || texelFetch(fogPushSampler, bb, 0).r == 0u) continue;
        vec3 w = mix(1.0 - f, f, vec3(o));
        s += w.x * w.y * w.z;
    }
    return s;
}

void main() {
    ivec2 cxz = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(cxz, GFOG_CELLS.xz))) return;
    bool even = (frameCounter & 1) == 0;

    // transición del bioma
    float prevFade = mrState.fogFade[even ? 1 : 0];
    if (isnan(prevFade) || isinf(prevFade)) prevFade = 0.0;
#ifdef BIOME_DEEP_DARK
    float want = biome == BIOME_DEEP_DARK ? 1.0 : 0.0;
#else
    float want = 0.0;
#endif
    float fade = clamp(mix(prevFade, want, 1.0 - exp(-frameTime * 0.8)), 0.0, 1.0);
    if (cxz == ivec2(0)) mrState.fogFade[even ? 0 : 1] = fade;
    // apagada
    if (fade < 0.0005 && prevFade < 0.0005) return;

    ivec3 shift = (cameraPositionInt - previousCameraPositionInt) * GFOG_P;
    float relax = 1.0 - exp(-frameTime * 2.0);
    // esquina del volumen en el mundo (envuelta)
    vec3 originW = vec3((cameraPositionInt & 2047) - GFOG_HALF);

    float floorTop = -1e6;
    int lastBy = -1;
    bool inside = false;
    ivec3 vox0 = ivec3(cxz.x / GFOG_P.x, 0, cxz.y / GFOG_P.z) - GFOG_HALF + VOXEL_HALF;
    float vals[GFOG_CELLS.y];
    for (int cy = 0; cy < GFOG_CELLS.y; cy++) {
        ivec3 cell = ivec3(cxz.x, cy, cxz.y);
        int by = cy / GFOG_P.y;
        if (by != lastBy) {
            lastBy = by;
            ivec3 vox = ivec3(vox0.x, by - GFOG_HALF.y + VOXEL_HALF, vox0.z);
            uint d = inVoxelVolume(vox) ? voxelData(vox) : 0u;
            inside = false;
            if (voxelFullCube(d)) {
                inside = true;
                floorTop = float(by + 1);
            } else if ((d & VOX_SOLID) != 0u && (d & VOX_PARTIAL) != 0u) {
                // losas y escaleras: sin niebla
                inside = true;
                floorTop = -1e6;
            } else if ((d & VOX_WATER) != 0u) {
                inside = true;
                floorTop = float(by) + 0.9;
            }
        }

        vec3 q = (vec3(cell) + 0.5) / vec3(GFOG_P);
        float target = 0.0;
        if (!inside && fade > 0.001) {
            float h = q.y - floorTop;
            if (h < GROUND_FOG_HEIGHT * 1.4) target = gfogTarget(originW + q, h) * fade;
        }

        float val = 0.0;
        if (!inside) {
            ivec3 pc = cell + shift;
            float prev = target;
            if (gfogInCells(pc)) prev = even ? texelFetch(fogSamplerB, pc, 0).r : texelFetch(fogSamplerA, pc, 0).r;
            if (isnan(prev) || isinf(prev)) prev = 0.0;
            val = mix(prev, target, relax);
            if (val > 0.002) val *= exp(-frameTime * 10.0 * pushAt(q));
        }

        vals[cy] = val;
        // bloques con niebla
        if (val > 0.004) imageAtomicMax(fogMaskImg, cell / GFOG_P, 1u);
    }

    // sombra propia
    float above = 0.0;
    for (int cy = GFOG_CELLS.y - 1; cy >= 0; cy--) {
        ivec3 cell = ivec3(cxz.x, cy, cxz.y);
        vec4 o = vec4(vals[cy], exp(-above * 2.5), 0.0, 0.0);
        if (even) imageStore(fogImgA, cell, o);
        else imageStore(fogImgB, cell, o);
        above += vals[cy] / float(GFOG_P.y);
    }
}

#else

void main() {}

#endif
