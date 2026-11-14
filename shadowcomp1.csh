#version 430

// Floodfill de luz de color, una iteración por frame: máximo de los vecinos (6 caras + 12 aristas) con caída, teñido
// por el cristal. Lee el frame anterior (desplazado con la cámara) y escribe en la otra imagen.

#include "/lib/settings.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 16, 16);

#ifdef FLOODFILL

#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#define VOXEL_READ
#include "/lib/voxel.glsl"

layout(rgba16f) writeonly uniform image3D lightImgA;
layout(rgba16f) writeonly uniform image3D lightImgB;
layout(rgba16f) writeonly uniform image3D lightDirImg;
#ifdef LEAF_SSS
layout(rg16f) writeonly uniform image3D foliageOccImg;
#endif

vec3 prevLight(ivec3 p) {
    if (!inVoxelVolume(p)) return vec3(0.0);
    // pares: escribe A, lee B
    if ((frameCounter & 1) == 0) return texelFetch(lightSamplerB, p, 0).rgb;
    return texelFetch(lightSamplerA, p, 0).rgb;
}

// Paso por un vecino: 0 si es sólido, su color si es cristal tintado
vec3 neighborPass(ivec3 p, out bool blocks) {
    blocks = false;
    if (!inVoxelVolume(p)) return vec3(1.0);
    uint dn = voxelData(p);
    blocks = voxelBlocksLight(dn);
    if (blocks) return vec3(0.0);
#ifdef TINTED_LIGHT
    if ((dn & VOX_TINT) != 0u) return tintColor(int((dn >> 8u) & 255u));
#endif
    return vec3(1.0);
}

// gradiente de luminancia en un eje (de un lado junto a sólidos)
float lumGrad(float lc, vec3 lp, bool bp, vec3 ln, bool bn) {
    float a = bp ? lc : luminance(lp);
    float b = bn ? lc : luminance(ln);
    float span = float(!bp) + float(!bn);
    return span > 0.0 ? (a - b) / span : 0.0;
}

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);
    if (!inVoxelVolume(v)) return;

    ivec3 pv = v + (cameraPositionInt - previousCameraPositionInt);
    uint d = voxelData(v);
    int id = int((d >> 8u) & 255u);
#ifdef LEAF_SSS
    imageStore(foliageOccImg, v, vec4(foliageOcc(d), 0.0, 0.0));
#endif

    // 6 caras: luz anterior y si bloquean
    vec3 lpx = vec3(0.0), lnx = vec3(0.0), lpy = vec3(0.0), lny = vec3(0.0), lpz = vec3(0.0), lnz = vec3(0.0);
    bool px = true, nx = true, py = true, ny = true, pz = true, nz = true;
    bool open = !voxelBlocksLight(d);

    vec3 L = vec3(0.0);
    if (open) {
        float fa = FLOODFILL_FALLOFF;
        float fe = pow(FLOODFILL_FALLOFF, 1.41421);

        lpx = prevLight(pv + ivec3( 1, 0, 0));
        lnx = prevLight(pv + ivec3(-1, 0, 0));
        lpy = prevLight(pv + ivec3( 0, 1, 0));
        lny = prevLight(pv + ivec3( 0,-1, 0));
        lpz = prevLight(pv + ivec3( 0, 0, 1));
        lnz = prevLight(pv + ivec3( 0, 0,-1));
        L = max(max(max(lpx, lnx), max(lpy, lny)), max(lpz, lnz)) * fa;

        // aristas: por una de las dos caras intermedias
        vec3 tpx = neighborPass(v + ivec3( 1, 0, 0), px);
        vec3 tnx = neighborPass(v + ivec3(-1, 0, 0), nx);
        vec3 tpy = neighborPass(v + ivec3( 0, 1, 0), py);
        vec3 tny = neighborPass(v + ivec3( 0,-1, 0), ny);
        vec3 tpz = neighborPass(v + ivec3( 0, 0, 1), pz);
        vec3 tnz = neighborPass(v + ivec3( 0, 0,-1), nz);

        L = max(L, prevLight(pv + ivec3( 1, 1, 0)) * fe * max(tpx, tpy));
        L = max(L, prevLight(pv + ivec3(-1, 1, 0)) * fe * max(tnx, tpy));
        L = max(L, prevLight(pv + ivec3( 1,-1, 0)) * fe * max(tpx, tny));
        L = max(L, prevLight(pv + ivec3(-1,-1, 0)) * fe * max(tnx, tny));
        L = max(L, prevLight(pv + ivec3( 1, 0, 1)) * fe * max(tpx, tpz));
        L = max(L, prevLight(pv + ivec3(-1, 0, 1)) * fe * max(tnx, tpz));
        L = max(L, prevLight(pv + ivec3( 1, 0,-1)) * fe * max(tpx, tnz));
        L = max(L, prevLight(pv + ivec3(-1, 0,-1)) * fe * max(tnx, tnz));
        L = max(L, prevLight(pv + ivec3( 0, 1, 1)) * fe * max(tpy, tpz));
        L = max(L, prevLight(pv + ivec3( 0,-1, 1)) * fe * max(tny, tpz));
        L = max(L, prevLight(pv + ivec3( 0, 1,-1)) * fe * max(tpy, tnz));
        L = max(L, prevLight(pv + ivec3( 0,-1,-1)) * fe * max(tny, tnz));

#ifdef TINTED_LIGHT
        if ((d & VOX_TINT) != 0u) L *= tintColor(id);
#endif
        if ((d & VOX_LEAVES) != 0u) L *= 0.65;
    }

    if ((d & VOX_EMITTER) != 0u) {
        float level = float((d >> 16u) & 15u) / 15.0;
        L = max(L, emitterColor(id) * level);
    }
#if PBR_GLOW_LIGHT > 0
    // Textura que brilla: sólida pero emite; rodeada de otras que brillan, menos
    if ((d & VOX_PBRGLOW) != 0u) {
        uint gw = voxelSlot(v, SLOT_GLOW);
        float crowd = 0.0;
        for (int k = 0; k < 6; k++) {
            ivec3 nb = v + ivec3(k == 0 ? 1 : (k == 1 ? -1 : 0), k == 2 ? 1 : (k == 3 ? -1 : 0), k == 4 ? 1 : (k == 5 ? -1 : 0));
            if (inVoxelVolume(nb) && (voxelData(nb) & VOX_PBRGLOW) != 0u) crowd += 1.0;
        }
        L = max(L, pbrGlowColor(gw) * (float(pbrGlowLevel(gw)) / 15.0 / (1.0 + crowd * 0.75)));
    }
#endif
#ifdef XP_ORB_GLOW
    if ((d & VOX_XP) != 0u) L = max(L, XP_LIGHT_COLOR * (float(XP_ORB_LIGHT) / 15.0));
#endif
    if ((d & VOX_CRYSTAL) != 0u) L = max(L, END_CRYSTAL_LIGHT);
    if ((d & VOX_FIRE) != 0u) L = max(L, ENTITY_FIRE_LIGHT);

    if (any(isnan(L)) || any(isinf(L))) L = vec3(0.0);
    L = clamp(L, vec3(0.0), vec3(4.0));

    if ((frameCounter & 1) == 0) imageStore(lightImgA, v, vec4(L, 1.0));
    else imageStore(lightImgB, v, vec4(L, 1.0));

    // Dirección hacia la luz, por vóxel (por celda en gbuffers las caras parpadean)
    vec3 dir = vec3(0.0);
    if (open) {
        float lc = luminance(L);
        vec3 g = vec3(lumGrad(lc, lpx, px, lnx, nx), lumGrad(lc, lpy, py, lny, ny), lumGrad(lc, lpz, pz, lnz, nz));
        float gl = length(g);
        if (gl > 1e-5 && lc > 1e-4) dir = g / gl * saturate(gl / lc * 2.5);
    }
    imageStore(lightDirImg, v, vec4(dir, 0.0));
}

#else

void main() {}

#endif
