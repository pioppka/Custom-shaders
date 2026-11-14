// Composite 4: bordes, reflejos y niebla

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

#define SHADOW_SAMPLING
#ifdef FLOODFILL
    #define VOXEL_READ
#endif
#include "/lib/sky.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;

#include "/lib/raytrace.glsl"
#include "/lib/translucent.glsl"
#include "/lib/reflect.glsl"

#ifdef PLASTIC_REFLECTIONS
uniform sampler2D colortex7;
#endif
#ifdef WATER_SIM
uniform sampler2D colortex5;
#endif

#if defined FLOODFILL && defined GROUND_FOG
    #define GROUND_FOG_READ
#include "/lib/groundfog.glsl"
uniform sampler3D fogSamplerA;
uniform sampler3D fogSamplerB;
uniform usampler3D fogMaskSampler;
#include "/lib/state.glsl"
#endif

in vec2 uv;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

// ------------------------------------------------------------------ bordes
vec3 edgeMaterialTint(vec3 c) { return saturateColor(c / max(max3(c), 1e-4), 1.5); }

// Hoja: ¿el vecino q está fuera de la copa? Se mira en los vóxeles hasta 3 bloques detrás.
bool leafOutside(ivec2 q, vec2 res, vec3 vpos, bool sky) {
#ifdef FLOODFILL
    vec3 ray = screenToView((vec2(q) + 0.5) / res, 1.0);
    vec3 side = ray * (vpos.z / ray.z) - vpos;
    float sl = length(side);
    if (sl < 1e-6) return sky;
    side /= sl;
    vec3 viewDir = normalize(vpos);
    for (int k = 0; k < 6; k++) {
        vec3 pv = vpos + side + viewDir * (0.6 * float(k));
        ivec3 v = playerToVoxel(viewToPlayer(pv));
        if (inVoxelVolume(v) && (voxelData(v) & VOX_LEAVES) != 0u) return false;
    }
    return true;
#else
    return sky;   // sin vóxeles: sólo contra el cielo
#endif
}

// Grosor en píxeles de pantalla; de cerca hasta 2.5 veces. depth: profundidad en vista
int edgePixels(float width, float depth) {
    float scale = max(viewSize().y / 1080.0, 1.0);
    float texelPx = gbufferProjection[1][1] * viewSize().y / (32.0 * max(depth, 0.05));
    return max(1, int(clamp(width * texelPx / 3.0, width * scale, 2.5 * width * scale) + 0.5));
}

// Arista convexa o silueta. foliageOuter: hojas sin vóxeles. silOut / silBlockOut: silueta y luz de bloque del fondo
float edgeMask(ivec2 px, vec3 vpos, vec3 nView, bool foliageOuter, bool isLeaf, int w, out float silOut, out float silBlockOut) {
    vec2 res = viewSize();
    const ivec2 dirs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
    float m = 0.0;
    silOut = 0.0;
    silBlockOut = 0.0;
    for (int i = 0; i < 4; i++) {
        ivec2 q = clamp(px + dirs[i] * w, ivec2(0), ivec2(res) - 1);
        float dq = texelFetch(depthtex0, q, 0).r;
        if (dq >= SKY_DEPTH) {
            m = 1.0;
            if (!isLeaf || leafOutside(q, res, vpos, true)) silOut = 1.0;
            continue;
        }
        vec3 pq = screenToView((vec2(q) + 0.5) / res, dq);
        vec3 dv = pq - vpos;
        float dl = length(dv);
        if (dl < 1e-4) continue;
        float behind = -dot(dv, nView);
        vec4 gq = texelFetch(colortex1, q, 0);
        bool qLeaf = decodeMaterial(gq.b) == MAT_FOLIAGE;
        bool leafNear = qLeaf && behind < 2.5;
        float silhouette = smoothstep(0.30, 0.80, behind);
        // en hojas, otras hojas no son fondo
        if (!isLeaf || (!qLeaf && silhouette > 0.0 && leafOutside(q, res, vpos, false))) {
            silOut = max(silOut, silhouette);
            silBlockOut = max(silBlockOut, decodeBlockLight(gq.b) * silhouette);
        }
        if (foliageOuter && leafNear) continue;
        vec3 nq = mat3(gbufferModelView) * decodeNormal(gq.rg);
        float crease = smoothstep(0.20, 0.45, behind / dl) * smoothstep(0.25, 0.60, 1.0 - dot(nq, nView));
        m = max(m, max(crease, silhouette));
    }
    return m;
}

#ifdef BACKLIGHT
// ------------------------------------------------------------------ contraluz
// Luz del sol, la luna o los bloques detrás de lo que se ve. lmFront / lmBehind: luz de bloque delante y detrás (sin
// floodfill).
vec3 backlightColor(vec3 ppos, float dist, vec3 N, float skyL, float lmFront, float lmBehind) {
    vec3 viewDir = ppos / max(dist, 1e-4);
    vec3 rim = vec3(0.0);

    vec3 L = lightDirWorld();
#ifdef SSS_GLOBAL
    // donde llega la luz; de espaldas al sol, la sombra 1.5 bloques hacia él (lo fino brilla)
    float skyFade = mainLightFade(skyL);
    if (skyFade > 0.001) {
        vec3 q = (floor((ppos - N * 0.01 + cameraPositionFract) * 16.0) + 0.5) / 16.0 - cameraPositionFract;
        vec3 sh = dot(N, L) > 0.0 ? getShadow(q, N) : getShadow(q + L * 1.5, L);
        rim += celestialEdgeColor() * sh * (skyFade * mix(0.5, 1.0, dayFactor()));
    }
    #ifdef FLOODFILL
    vec3 ffFront, ffBack, dirF, dirB;
    float wF = sampleFloodfill(ppos, N, ffFront, dirF);
    float wB = sampleFloodfill(ppos + viewDir * 0.7, viewDir, ffBack, dirB);
    vec3 blk = max(ffFront * wF, ffBack * wB) * (FLOODFILL_BRIGHTNESS * 1.3) * (1.0 - blockLightDayWeight(skyL));
    #else
    float lm = max(pow(lmFront, 2.4), pow(lmBehind, 2.4)) * 1.3;
    vec3 blk = vec3(1.0, 0.62, 0.32) * (lm * BLOCKLIGHT_BRIGHTNESS * (1.0 - blockLightDayWeight(skyL)));
    #endif
    rim += blk / max(1.0, max3(blk)) * BACKLIGHT_BLOCKLIGHT;
#else
    // luz por detrás (menos de ~60° de la vista)
    float back = smoothstep(0.50, 0.95, dot(viewDir, L));
    float skyFade = mainLightFade(skyL);
    if (back * skyFade > 0.001) {
        vec3 q = (floor((ppos + cameraPositionFract) * 16.0) + 0.5) / 16.0 - cameraPositionFract;
        float night = mix(0.5, 1.0, dayFactor());
        rim += celestialEdgeColor() * getShadow(q + L * 1.5, L) * (back * skyFade * night);
    }
#ifdef FLOODFILL
    // luces de bloque al otro lado
    vec3 ffBack, ffFront, dirB, dirF;
    float wB = sampleFloodfill(ppos + viewDir * 0.7, viewDir, ffBack, dirB);
    float wF = sampleFloodfill(ppos, N, ffFront, dirF);
    float dl = length(dirB);
    float fromBehind = dl > 1e-5 ? smoothstep(-0.1, 0.5, dot(dirB / dl, viewDir)) * saturate(dl / 0.25) : 0.0;
    vec3 blk = max(ffBack * wB * fromBehind, ffBack * wB - ffFront * wF);
    blk = max(blk, vec3(0.0)) * (FLOODFILL_BRIGHTNESS * 1.3) * (1.0 - blockLightDayWeight(skyL));
    rim += blk / max(1.0, max3(blk)) * BACKLIGHT_BLOCKLIGHT;
#else
    // sin floodfill: más luz de bloque en el fondo que delante
    float behind = max(pow(lmBehind, 2.4) - pow(lmFront, 2.4), 0.0) * 1.3;
    vec3 blk = vec3(1.0, 0.62, 0.32) * (behind * BLOCKLIGHT_BRIGHTNESS * (1.0 - blockLightDayWeight(skyL)));
    rim += blk / max(1.0, max3(blk)) * BACKLIGHT_BLOCKLIGHT;
#endif
#endif
    return rim * BACKLIGHT_STRENGTH;
}
#endif

#ifdef CLOUD_RIM
// ------------------------------------------------------------------ borde de las nubes
// Franja en la silueta de las nubes, más fuerte del lado del sol
vec3 cloudRim(ivec2 px, vec3 vpos, vec3 viewDir) {
    vec3 L = lightDirWorld();
    float phase = 0.12 + 0.88 * pow(saturate(dot(viewDir, L) * 0.5 + 0.5), 4.0);
    vec3 rimCol = celestialEdgeColor() * (phase * (1.0 - undergroundFactor()));
    if (max3(rimCol) < 0.002) return vec3(0.0);

    vec2 res = viewSize();
    // dirección del sol en pantalla
    vec3 Lv = mat3(gbufferModelView) * L;
    vec2 toSun = (viewToScreen(vpos + Lv * (0.05 * length(vpos))).xy - viewToScreen(vpos).xy) * res;
    toSun = dot(toSun, toSun) > 1e-6 ? normalize(toSun) : vec2(0.0);

    int w = max(1, int(3.0 * res.y / 1080.0 + 0.5));
    float behind = length(vpos) * 1.2 + 4.0;
    float rim = 0.0;
    for (int i = 0; i < 8; i++) {
        vec2 d = vec2(cos(float(i) * 0.7853982), sin(float(i) * 0.7853982));
        ivec2 q = clamp(px + ivec2(round(d * float(w))), ivec2(0), ivec2(res) - 1);
        float dq = texelFetch(depthtex0, q, 0).r;
        if (dq >= SKY_DEPTH || length(screenToView((vec2(q) + 0.5) / res, dq)) > behind) {
            rim = max(rim, 0.35 + 0.65 * saturate(dot(d, toSun)));
        }
    }
    return rimCol * (rim * CLOUD_RIM_STRENGTH);
}
#endif

//------------------------------------------------------------------ niebla
vec3 applyFog(vec3 col, vec3 ppos, float dist, bool cloud) {
    vec3 dir = ppos / max(dist, 1e-4);

    if (isEyeInWater == 1) {
        vec3 wc = toLinear(fogColor) * (ambientSkyLight() * 1.5 + celestialLightColor() * 0.3 + vec3(0.03));

        //vec3 wc = texelFetch(waterFogSampler, ivec2(0), 0).rgb;
	//vec3 wc = fogWaterColor;

        return mix(
            col * mix(vec3(1.0), vec3(0.60, 0.85, 1.0), UNDERWATER_FOG),
            wc,
            1.0 - exp(-dist * 0.07 * UNDERWATER_FOG)
        );

        //vec3 wc = vec3(0.02, 0.24, 0.40) * (ambientSkyLight() * 1.5 + celestialLightColor() * 0.3 + vec3(0.03));
        // UNDERWATER_FOG: densidad y tinte
        //return mix(col * mix(vec3(1.0), vec3(0.60, 0.85, 1.0), UNDERWATER_FOG), wc, 1.0 - exp(-dist * 0.07 * UNDERWATER_FOG));
    }

    if (isEyeInWater == 2) return mix(col, vec3(1.0, 0.35, 0.05), 1.0 - exp(-dist * 0.8));
    if (isEyeInWater == 3) return mix(col, vec3(0.75, 0.82, 0.90), 1.0 - exp(-dist * 0.6));

    float f;
    if (overworldSky()) f = 1.0 - exp(-dist * (0.0010 + rainStrength * 0.0060) * FOG_DENSITY);
    else if (hasCeiling) f = 1.0 - exp(-dist * 0.012 * FOG_DENSITY);
    else f = 1.0 - exp(-dist * (0.004 * FOG_DENSITY + 0.003));   // End: algo de bruma
#ifdef BORDER_FOG
    if (!cloud) f = max(f, smoothstep(far * 0.72, far * 0.98, dist));
#endif
    // nubes lejanas: color del cielo
    if (cloud) f = min(f * 0.6, 0.55);
    col = mix(col, fogColorDir(dir), saturate(f));
    // desde una cueva, más oscuras
    if (cloud) col = mix(col, CAVE_SKY, undergroundFactor());

    float blind = max(blindness, darknessFactor);
    col *= mix(1.0, exp(-dist * 0.25), blind);
    return col;
}

#ifdef GROUND_FOG_READ
// ------------------------------------------------------------------ niebla de suelo
// Distancia de salida de la caja [lo, hi]
float boxExit(vec3 o, vec3 invD, vec3 lo, vec3 hi) {
    vec3 t = mix(lo, hi, step(0.0, invD)) - o;
    return min3(t * invD);
}

// Marcha a pasos crecientes con lectura trilineal, saltando bloques sin niebla; luz del floodfill
vec3 applyGroundFog(vec3 col, vec3 dir, float dist) {
    float fade = mrState.fogFade[(frameCounter & 1) == 0 ? 0 : 1];
    if (!(fade > 0.001)) return col;
    bool even = (frameCounter & 1) == 0;

    vec3 o = cameraPositionFract + vec3(GFOG_HALF);
    vec3 d = dir;
    vec3 invD = 1.0 / vec3(abs(d.x) < 1e-6 ? 1e-6 : d.x, abs(d.y) < 1e-6 ? 1e-6 : d.y, abs(d.z) < 1e-6 ? 1e-6 : d.z);
    float tEnd = min(min(dist, GFOG_DIST), boxExit(o, invD, vec3(0.0), vec3(GFOG_BLOCKS)));
    vec3 toUvw = vec3(GFOG_P) / vec3(GFOG_CELLS);
    // luz algo más arriba: dentro del piso es 0
    vec3 toLight = vec3(0.0, 0.35, 0.0) - vec3(GFOG_HALF) + float(VOXEL_HALF);

    const vec3 baseLight = vec3(0.030, 0.060, 0.070);
    float sigma = 0.8 * GROUND_FOG_DENSITY;
    float T = 1.0;
    vec3 C = vec3(0.0);
    float t = 0.0;
    for (int i = 0; i < 256 && t < tEnd; i++) {
        vec3 q = o + d * t;
        ivec3 b = ivec3(floor(q + d * 1e-3));
        if (!gfogInBlocks(b)) break;
        if (texelFetch(fogMaskSampler, b, 0).r == 0u) {
            t = boxExit(o, invD, vec3(b), vec3(b) + 1.0) + 1e-3;
            continue;
        }
        float seg = min(0.15 + 0.02 * t, tEnd - t);
        vec3 sp = q + d * (seg * 0.5);
        vec2 fd = even ? texture(fogSamplerA, sp * toUvw).rg : texture(fogSamplerB, sp * toUvw).rg;
        float dens = fd.r * (1.0 - smoothstep(GFOG_DIST * 0.7, GFOG_DIST, t));
        if (dens > 0.002) {
            float a = 1.0 - exp(-dens * sigma * seg);
            vec3 L = baseLight + vec3(0.35) * nightVision;
            vec3 lw = (sp + toLight) / float(VOXEL_SIZE);
            vec3 ff = even ? texture(lightSamplerA, lw).rgb : texture(lightSamplerB, lw).rgb;
            vec3 ffDir = texture(lightDirSampler, lw).xyz;
            float dl = length(ffDir);
            float toward = dl > 1e-4 ? pow(saturate(dot(d, ffDir / dl)), 4.0) * saturate(dl / 0.25) : 0.0;
            L += ff * (FLOODFILL_BRIGHTNESS * 1.1) * (1.0 + 1.5 * toward);
            L *= mix(0.35, 1.0, fd.g);
            C += T * a * L;
            T *= 1.0 - a;
            if (T < 0.02) break;
        }
        t += seg;
    }

    if (T > 0.998) return col;
    return col * T + C * GROUND_FOG_BRIGHTNESS;
}
#endif

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 col = texelFetch(colortex0, px, 0).rgb;
    float d0 = texelFetch(depthtex0, px, 0).r;

    if (d0 >= SKY_DEPTH) {
        if (isEyeInWater != 0 || blindness > 0.0 || darknessFactor > 0.0) {
            vec3 dir = normalize(mat3(gbufferModelViewInverse) * screenToView(uv, 1.0));
            col = applyFog(col, dir * far, far, false);
        }
        outColor = vec4(col, 1.0);
        return;
    }

    vec4 gdat = texelFetch(colortex1, px, 0);
    vec4 tdat = texelFetch(colortex6, px, 0);
    int mat = decodeMaterial(gdat.b);
    bool laterOpaque = mat == MAT_ENTITY || mat == MAT_HAND || mat == MAT_CLOUD || mat == MAT_TEXT || mat == MAT_BLOCKENTITY;
    bool transFront = tdat.w < 1.0 && (!laterOpaque || tdat.w <= d0 + 1e-6);

    vec3 N = decodeNormal(gdat.rg);
    float skyL = texelFetch(colortex4, px, 0).b;
    if (transFront) {
        float surfDepth;
        frontTranslucent(px, uv, tdat, d0, laterOpaque, surfDepth, N, mat, skyL);
        // ola suavizada para el reflejo
        if (mat == MAT_WATER && N.y > 0.5) N = normalize(mix(vec3(0.0, 1.0, 0.0), N, 0.3));
    }

    if (mat == MAT_TEXT) {
        outColor = vec4(col, 1.0);
        return;
    }

    vec3 vpos = screenToView(uv, d0);
    vec3 ppos = viewToPlayer(vpos);
    float dist = length(ppos);

    //------------------------------------------------ 1) bordes iluminados y contraluz
#if defined LIGHT_EDGES || defined BACKLIGHT
    if (!transFront && mat != MAT_NONE && mat != MAT_PORTAL) {
        float fadeE = 1.0 - smoothstep(48.0, 96.0, dist);
        vec3 baseCol = col;
        float strength = 0.0;
        bool foliageOuter = false;
    #ifdef LIGHT_EDGES
        strength = EDGE_STRENGTH;
        if (mat == MAT_FOLIAGE) {
    #if EDGE_LEAVES == 0
            strength = 0.0;
    #elif EDGE_LEAVES == 1
            // hojas: sólo el contorno de la copa
            vec3 an = abs(N);
            vec3 lp = fract(ppos + cameraPositionFract - N * 0.02);
            ivec3 t1 = an.x > 0.5 ? ivec3(0, 1, 0) : ivec3(1, 0, 0);
            ivec3 t2 = an.z > 0.5 ? ivec3(0, 1, 0) : ivec3(0, 0, 1);
            float u = dot(lp, vec3(t1));
            float v = dot(lp, vec3(t2));
            const float bw = 1.5 / 16.0;
            bool nu0 = u < bw;
            bool nu1 = u > 1.0 - bw;
            bool nv0 = v < bw;
            bool nv1 = v > 1.0 - bw;
            if (!(nu0 || nu1 || nv0 || nv1)) {
                strength = 0.0;
            } else {
        #ifdef FLOODFILL
                // cuenta si al lado no hay hoja ni sólido
                ivec3 vb = playerToVoxel(ppos - N * 0.02);
                if (inVoxelVolume(vb - t1) && inVoxelVolume(vb + t1) && inVoxelVolume(vb - t2) && inVoxelVolume(vb + t2)) {
                    const uint conn = VOX_LEAVES | VOX_SOLID;
                    bool outer = (nu0 && (voxelData(vb - t1) & conn) == 0u) || (nu1 && (voxelData(vb + t1) & conn) == 0u)
                              || (nv0 && (voxelData(vb - t2) & conn) == 0u) || (nv1 && (voxelData(vb + t2) & conn) == 0u);
                    if (!outer) strength = 0.0;
                } else {
                    foliageOuter = true;
                }
        #else
                foliageOuter = true;
        #endif
            }
    #endif
        }
    #endif
        if (fadeE > 0.0) {
            vec3 nView = mat3(gbufferModelView) * N;
            float sil;
            float silBlock;
            float edgeDepth = mat == MAT_HAND ? 1e4 : -vpos.z;   // la mano, con el grosor fijo
            int wEdge = edgePixels(EDGE_WIDTH, edgeDepth);
            float e = edgeMask(px, vpos, nView, foliageOuter, mat == MAT_FOLIAGE, wEdge, sil, silBlock);
    #ifdef BACKLIGHT
            // bordes SSS con su grosor
            int wBack = edgePixels(BACKLIGHT_WIDTH, edgeDepth);
            if (wBack != wEdge) edgeMask(px, vpos, nView, foliageOuter, mat == MAT_FOLIAGE, wBack, sil, silBlock);
    #endif
            if (strength > 0.001) {
                vec3 el = texelFetch(colortex2, px, 0).rgb;
        #if EDGE_COLOR == 1
                vec3 ec = vec3(luminance(el) * 1.3);
        #elif EDGE_COLOR == 2
                vec3 ec = edgeMaterialTint(baseCol) * (luminance(el) * 1.6);
        #else
                vec3 ec = saturateColor(el, 1.25);   // algo más saturado
        #endif
                col += ec * e * strength * fadeE * 0.6;
            }
    #ifdef BACKLIGHT
            if (sil > 0.001) {
                vec3 rim = backlightColor(ppos, dist, N, skyL, decodeBlockLight(gdat.b), silBlock);
        #if BACKLIGHT_TINT == 1
                rim = edgeMaterialTint(baseCol) * (luminance(rim) * 1.6);
        #elif BACKLIGHT_TINT == 2
                rim = vec3(luminance(rim) * 1.3);
        #endif
                col += rim * (sil * fadeE * 0.7 * DEBUG_LIGHTS.w);
            }
    #endif
        }
    }
#endif

    //------------------------------------------------ 2) reflejos pixelados
#if REFLECTION_MODE > 0
    float reflStrength = 0.0;
    float f0 = 0.04;
    bool metallic = false;
    if (transFront) {
        if (mat == MAT_WATER) {
            f0 = 0.02;
            reflStrength = WATER_REFLECTIVITY;
        #ifdef WATER_SIM
            // la espuma no refleja
            float foamA = texelFetch(colortex5, px, 0).a;
            reflStrength *= 1.0 - saturate((foamA - WATER_ALPHA) / (0.95 - WATER_ALPHA));
        #endif
        } else if (mat == MAT_GLASS || mat == MAT_ICE || mat == MAT_SLIME) {
            reflStrength = 0.8;
        }
    } else if (mat == MAT_PUDDLE) {
        f0 = 0.02;
        reflStrength = WATER_REFLECTIVITY;
    } else {
    #ifdef SMOOTH_REFLECTIONS
        vec4 pbr = texelFetch(colortex4, px, 0);
        metallic = pbr.g > 0.99;
        if (pbr.r > 0.72 || metallic) {
            reflStrength = saturate((pbr.r - 0.72) / 0.2);
            if (metallic) reflStrength = max(reflStrength, 0.6);
            f0 = metallic ? 0.7 : max(pbr.g, 0.04);
        }
    #endif
        if (mat == MAT_HAND || mat == MAT_CLOUD || mat == MAT_PORTAL || mat == MAT_NONE) reflStrength = 0.0;
    }

    // bajo el agua, sin reflejos
    if (reflStrength > 0.0 && dist < far && isEyeInWater != 1) {
        vec3 origin = snapToSurfaceGrid(ppos, N);
        vec3 V = normalize(origin);
        float F = fresnelSchlick(dot(-V, N), f0);
        if (mat == MAT_WATER || mat == MAT_PUDDLE) F = mix(0.20, 1.0, F);
        vec3 glow;
        vec3 rc = reflectionColorGlow(origin, N, V, skyL, 48, RT_STEPS, false, glow);
        if (metallic) {
            vec3 tint = col / max(max3(col), 0.05);
            rc *= tint;
            glow *= tint;
        }
        float Fr = saturate(F * reflStrength);
        // lo emisivo, con más peso
        col = mix(col, rc, Fr) + glow * mix(0.45, 1.0, Fr) * reflStrength;
    }

    //------------------------------------------------ 2b) reflejo plástico difuso
    #ifdef PLASTIC_REFLECTIONS
    float plastic = plasticReflectAmount(mat);
    if (!transFront && plastic > 0.0 && reflStrength <= 0.0 && isEyeInWater != 1) {
        vec4 g = texelFetch(colortex7, px, 0);
        vec3 Vp = normalize(ppos);
        float Fp = mix(0.10, 1.0, fresnelSchlick(dot(-Vp, N), 0.04));
        // con lluvia, más brillo al aire libre
        float wetBoost = 1.0 + 1.5 * wetness * smoothstep(0.95, 0.99, skyL);
        col = mix(col, g.rgb, saturate(Fp * PLASTIC_REFL_STRENGTH * plastic * wetBoost) * g.a);
    }
    #endif
#endif

#ifdef CLOUD_RIM
    //if (mat == MAT_CLOUD && !transFront) col += cloudRim(px, vpos, ppos / max(dist, 1e-4));
    if (mat == MAT_CLOUD && !transFront) {
        float horizonFade = smoothstep(0.02, 0.52, normalize(ppos).y);
        col += cloudRim(px, vpos, ppos / max(dist, 1e-4)) * horizonFade;
    }
#endif

    //------------------------------------------------ 3) niebla
#ifdef GROUND_FOG_READ
    if (mat != MAT_HAND) col = applyGroundFog(col, ppos / max(dist, 1e-4), dist);
#endif
    if (mat != MAT_HAND) col = applyFog(col, ppos, dist, mat == MAT_CLOUD);

    outColor = vec4(col, 1.0);
}

#endif
