#ifndef MRPIXEL_LIGHTING
#define MRPIXEL_LIGHTING

// Requiere: settings, uniforms, common, sky, shadows (SHADOW_SAMPLING), voxel (VOXEL_READ si FLOODFILL)

#include "/lib/sunshadow.glsl"

// Sombra del sol/luna: con vóxeles, sunshadow.glsl
vec3 sunShadowAt(vec3 pos, vec3 ng) {
#if defined SHADOW_SAMPLING && defined VOXEL_READ
    return getSunShadow(pos, ng);
#else
    return getShadow(pos, ng);
#endif
}

// Luz difusa del sol: continua, con la orilla de la sombra suave
float softDiffuse(float x) { return smoothstep(-0.10, 0.70, x); }

#ifndef FLOODFILL
uniform usampler2D fireLightSampler;

// Entidad que arde más cercana, como una fuente de nivel 15 sin sombras
float entityFireLight(vec3 pos) {
    if (texelFetch(fireLightSampler, ivec2(FIRE_LIGHTS, 0), 0).r == 0u) return 0.0;
    float best = 0.0;
    for (int i = 0; i < FIRE_LIGHTS; i++) {
        uint e = texelFetch(fireLightSampler, ivec2(i, 0), 0).r;
        if (e == 0u) continue;
        vec3 c = vec3(uvec3(e & 255u, (e >> 8u) & 255u, (e >> 16u) & 255u)) - 128.0;
        float d = length(pos + cameraPositionFract - (c * 2.0 + 1.0));
        best = max(best, pow(saturate(1.0 - d / 15.0), 2.4));
    }
    return best;
}
#endif

// Floodfill de color + lightmap (luces dinámicas incluidas)
vec3 getBlockLight(vec3 pos, vec3 ng, float lmBlock, out vec3 dir) {
    dir = vec3(0.0);
    const vec3 warm = vec3(1.0, 0.62, 0.32);
    float vanilla = pow(lmBlock, 2.4) * 1.3;
#ifndef FLOODFILL
    vanilla = max(vanilla, entityFireLight(pos + ng * 0.05) * 1.3);
#endif
    vec3 vanillaLight = warm * vanilla;
#ifdef FLOODFILL
    vec3 ff;
    vec3 ffDir;
    float w = sampleFloodfill(pos, ng, ff, ffDir);
    if (w > 0.0) {
        vec3 ffl = ff * FLOODFILL_BRIGHTNESS * 1.3;
        float extra = max(vanilla - max3(ffl) * 1.2, 0.0);
        dir = ffDir * w;
        return mix(vanillaLight, ffl + warm * extra, w) * BLOCKLIGHT_BRIGHTNESS;
    }
#endif
    return vanillaLight * BLOCKLIGHT_BRIGHTNESS;
}

#ifdef LEAF_SSS
#ifdef VOXEL_READ
uniform sampler3D foliageOccSampler;   // x hojas, y sólidos
#endif

// Sol que llega a hojas y plantas: marcha por la ocupación de vóxeles interpolada y luego la sombra suave del mapa
vec3 foliageSunLight(vec3 start, vec3 L) {
#ifdef VOXEL_READ
    vec3 base = start + cameraPositionFract + float(VOXEL_HALF) - 0.5;
    if (inVoxelVolume(ivec3(floor(base))) && inVoxelVolume(ivec3(floor(base + L * 7.0)))) {
        const float STEP = 0.55;
        float depth = 0.0;
        for (int k = 0; k < 12; k++) {
            vec2 occ = textureLod(foliageOccSampler, (base + L * (0.25 + STEP * float(k)) + 0.5) / float(2 * VOXEL_HALF), 0.0).rg;
            // bloques de hojas; lo sólido cuenta como 15
            depth += (occ.x + occ.y * 15.0) * STEP;
            if (depth > 8.0) return vec3(0.0);
        }
        return getShadowSoft(start + L * (0.25 + STEP * 12.0), L, L, 0.6) * leafTransmit(depth);
    }
#endif
    return vec3(getShadowThrough(start, L, L, 0.35));
}
#endif

struct LitOut {
    vec3 color;
    vec3 edgeLight;   // luz de los bordes
};

// N normal de sombreado, ng geométrica; posLight / posShadow en la rejilla de texels
LitOut shadeToon(vec3 albedo, vec3 N, vec3 ng, vec3 posLight, vec3 posShadow, vec2 lm, float ao,
                 float smoothness, float metal, float emission, float sss) {
    LitOut o;
    vec3 V = -normalize(posLight);
    vec3 L = lightDirWorld();
    vec3 sunCol = celestialLightColor();
    float skyFade = mainLightFade(lm.y);

    float NdotL = dot(N, L);
    float NgdotL = dot(ng, L);
    bool sunOn = skyFade > 0.0 && luminance(sunCol) > 1e-5;
    vec3 sssLight = vec3(0.0);
#ifdef LEAF_SSS
    vec3 shadow = vec3(0.0);
    vec3 leafSun = vec3(0.0);
    if (sss > 0.0 && sunOn) leafSun = foliageSunLight(posShadow + ng * 0.02, L);
    if (sunOn && NgdotL > -0.05) shadow = sss > 0.0 ? leafSun : sunShadowAt(posShadow, ng);
    float diff = softDiffuse(NdotL);
    vec3 sunLight = sunCol * diff * shadow * skyFade;
    // Hojas como medio translúcido: la luz sale por todas las caras, más hacia el sol
    if (sss > 0.0 && sunOn) {
        float wrap = 0.15 + 0.85 * smoothstep(0.3, -0.6, NgdotL);
        // Henyey-Greenstein, g = 0.5
        float phase = 0.5 + 0.5 * 0.75 / pow(1.25 - dot(-V, L), 1.5);
        sssLight = sunCol * leafSun * (LEAF_TRANSMIT * 2.5 * sss * wrap * phase * skyFade);
    }
#else
    vec3 ngL = (sss > 0.0 && NgdotL < 0.0) ? -ng : ng;
    vec3 shadow = vec3(0.0);
    if (sunOn && (NgdotL > -0.05 || sss > 0.0)) shadow = sunShadowAt(posShadow, ngL);
    float diff = softDiffuse(NdotL);
    if (sss > 0.0) diff = mix(diff, softDiffuse(abs(NdotL) * 0.7 + 0.15), sss);
    vec3 sunLight = sunCol * diff * shadow * skyFade;
#endif

    vec3 amb = overworldSky() ? ambientSkyLight() * (lm.y * lm.y * 0.85 + lm.y * 0.15) : ambientSkyLight();
    // el cielo ilumina más las caras de arriba que los lados y las de abajo
    if (overworldSky()) amb *= 0.75 + 0.25 * N.y;
    amb *= ao;
    amb += vec3(0.35) * nightVision * ao;
    vec3 minLight = vec3(0.100, 0.110, 0.140) * MIN_LIGHT * ao;

    vec3 blDir;
    vec3 bl = getBlockLight(posLight, ng, lm.x, blDir);
    bl = limitBlockLight(bl, sunLight + amb, lm.y);
    float blStrength = length(blDir);
    vec3 blDirN = blStrength > 0.001 ? blDir / blStrength : N;
    float blShade = mix(1.0, 0.45 + 0.55 * saturate(dot(N, blDirN) + 0.35), blStrength);
    vec3 blockDiffuse = bl * blShade * ao;

    // DEBUG_LIGHTS
    sunLight *= DEBUG_LIGHTS.x;
    shadow *= DEBUG_LIGHTS.x;
    amb *= DEBUG_LIGHTS.y;
    minLight *= DEBUG_LIGHTS.y;
    blockDiffuse *= DEBUG_LIGHTS.z;
    sssLight *= DEBUG_LIGHTS.w;
    vec3 color = albedo * (sunLight + amb + blockDiffuse + minLight) * (1.0 - metal * 0.8);
    // tono de la hoja con un brillo mínimo
    color += saturateColor(albedo, 1.3) * clamp(0.45 / max(max3(albedo), 1e-3), 1.0, 4.0) * sssLight;

#if defined LEAF_SSS && defined VOXEL_READ
    // Lo mismo con luces de bloque, con la dirección del vóxel de la hoja
    ivec3 vLeaf = playerToVoxel(posLight - ng * 0.05);
    vec3 dirV = (sss > 0.0 && inVoxelVolume(vLeaf)) ? texelFetch(lightDirSampler, vLeaf, 0).xyz : vec3(0.0);
    float strV = length(dirV);
    if (sss > 0.0 && strV > 0.02 && luminance(bl) > 1e-4) {
        vec3 dirN = dirV / strV;
        // ~0.4 como mucho
        float backB = smoothstep(0.10, 0.80, dot(-V, dirN)) * saturate(strV / 0.25);
        if (backB > 0.0) {
            vec3 c = vec3(vLeaf) + 0.5;
            float layers = 0.0;
            for (int k = 1; k <= 2; k++) {
                ivec3 v = ivec3(floor(c + dirN * float(k)));
                if (inVoxelVolume(v) && (voxelData(v) & (VOX_LEAVES | VOX_SOLID)) != 0u) layers += 1.0;
            }
            float transB = layers < 0.5 ? 1.0 : (layers < 1.5 ? 0.35 : 0.0);
            color += albedo * bl * (backB * transB * sss * LEAF_SSS_STRENGTH * 1.2 * DEBUG_LIGHTS.w);
        }
    }
#endif
#if defined LEAF_SSS && !defined VOXEL_READ
    // sin floodfill: igual por todas las caras
    if (sss > 0.0) color += saturateColor(albedo, 1.3) * bl * (LEAF_TRANSMIT * sss * 0.5 * DEBUG_LIGHTS.w);
#endif

    color += albedo * emission * (EMISSIVE_BRIGHTNESS * DEBUG_LIGHTS.z);

    // luz de bloques normalizada para conservar el tono
    vec3 blEdge = bl * (0.35 + 0.65 * blStrength) * saturate(dot(N, blDirN) + 0.6) * DEBUG_LIGHTS.z;
    // de noche, más tenues
    o.edgeLight = celestialEdgeColor() * mix(0.35, 1.0, dayFactor()) * shadow * skyFade * saturate(NdotL + 0.30)
                + blEdge / max(1.0, max3(blEdge)) * BLOCKLIGHT_RIM;
    o.color = color;
    return o;
}

#endif
