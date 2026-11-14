// Iluminación forward: terreno, bloques-entidad, entidades, mano. Salidas: colortex0 color, colortex1 normal +
// material, colortex2 luz de bordes, colortex4 PBR

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#if defined PROGRAM_ENTITIES || defined PROGRAM_ENTITIES_TRANSLUCENT || defined PROGRAM_HAND || defined PROGRAM_GENERIC
    #define ENTITY_LIKE
    // texturas de entidades: píxeles grandes, rejilla de sombras doble
    #define SHADOW_SNAP_SCALE (PIXEL_SHADOW_SCALE * 2.0)
#endif

//==============================================================================
#ifdef VERTEX_SHADER

#include "/lib/waving.glsl"

in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_tangent;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 vcolor;
out vec3 playerPos;
out vec3 worldNormal;
out vec4 worldTangent;
flat out int blockId;
#ifdef ENTITY_LIKE
uniform int entityId;
flat out int entityKind;
#endif

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
#ifdef ENTITY_LIKE
    entityKind = entityId;
#endif
    lmcoord = saturate(gl_MultiTexCoord1.xy / 240.0);
    vcolor = gl_Color;
    blockId = int(max(mc_Entity.x, 0.0) + 0.5);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = viewToPlayer(viewPos.xyz);

    vec3 n = gl_NormalMatrix * gl_Normal;
    worldNormal = dot(n, n) > 1e-8 ? mat3(gbufferModelViewInverse) * normalize(n) : vec3(0.0, 1.0, 0.0);
    vec3 t = gl_NormalMatrix * at_tangent.xyz;
    worldTangent = vec4(dot(t, t) > 1e-8 ? mat3(gbufferModelViewInverse) * normalize(t) : vec3(0.0), at_tangent.w);

#ifdef PROGRAM_TERRAIN
    vec3 wave = wavingOffset(playerPos, blockId, texcoord, mc_midTexCoord.xy);
    if (dot(wave, wave) > 0.0) {
        playerPos += wave;
        viewPos.xyz = playerToView(playerPos);
    }
#endif

    gl_Position = gl_ProjectionMatrix * viewPos;
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
#include "/lib/pixel.glsl"
#include "/lib/lighting.glsl"
#include "/lib/rain.glsl"
#include "/lib/lightmeter.glsl"

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform vec4 entityColor;
#ifdef PROGRAM_ENTITIES_TRANSLUCENT
uniform sampler2D depthtex1;   // sin translúcidos
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 vcolor;
in vec3 playerPos;
in vec3 worldNormal;
in vec4 worldTangent;
flat in int blockId;
#ifdef ENTITY_LIKE
flat in int entityKind;
#endif

// Lo que se dibuja después de las partículas borra las que tiene detrás (outHideParticles)
#if defined PROGRAM_ENTITIES_TRANSLUCENT || defined PROGRAM_ENTITIES || defined PROGRAM_BLOCK
    #define HIDES_PARTICLES
#endif

#ifdef HIDES_PARTICLES
/* RENDERTARGETS: 0,1,2,4,5 */
#else
/* RENDERTARGETS: 0,1,2,4 */
#endif
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outEdge;
layout(location = 3) out vec4 outPbr;

#ifdef HIDES_PARTICLES
// Partículas en su capa (colortex5); lo que se dibuja después borra lo que tiene detrás (blend en
// shaders.properties).
layout(location = 4) out vec4 outHideParticles;
#endif

#if defined ENTITY_LIKE && defined PLAYER_STUDIO_LIGHT
// Luces de estudio fijas a la cámara (arriba a la izquierda, derecha, detrás): lóbulos anchos sobre el reflejo
vec3 studioReflection(vec3 N, vec3 pos, vec2 lm) {
    vec3 n = mat3(gbufferModelView) * N;
    vec3 v = normalize(mat3(gbufferModelView) * pos);
    vec3 r = reflect(v, n);
    float env = 1.00 * pow(saturate(dot(r, normalize(vec3(-0.55, 0.65, 0.52)))), 6.0)
              + 0.35 * pow(saturate(dot(r, normalize(vec3(0.70, 0.20, 0.68)))), 4.0)
              + 0.60 * pow(saturate(dot(r, normalize(vec3(0.00, 0.30, -0.95)))), 3.0)
              + 0.40 * pow(saturate(r.y), 2.0);
    float fres = mix(0.15, 1.0, pow(1.0 - saturate(dot(n, -v)), 5.0));
    vec3 light = (ambientSkyLight() * 1.6 + celestialLightColor() * 0.6) * lm.y
               + vec3(1.0, 0.75, 0.5) * (pow(lm.x, 2.4) * BLOCKLIGHT_BRIGHTNESS * 0.6) + vec3(0.03);
    return light * (env * fres);
}
#endif

void main() {
#ifdef HIDES_PARTICLES
    outHideParticles = vec4(0.0);
#endif
    // derivadas antes de las ramas
    vec2 texSize = vec2(textureSize(gtexture, 0));
#ifdef ENTITY_LIKE
    vec2 uvT = texcoord * texSize * SHADOW_SNAP_SCALE;
#else
    vec2 uvT = texcoord * texSize * PIXEL_SHADOW_SCALE;
#endif
    vec2 dTdx = dFdx(uvT);
    vec2 dTdy = dFdy(uvT);
    vec3 dPdx = dFdx(playerPos);
    vec3 dPdy = dFdy(playerPos);
    vec2 dLdx = dFdx(lmcoord);
    vec2 dLdy = dFdy(lmcoord);
    float dAdx = dFdx(vcolor.a);
    float dAdy = dFdy(vcolor.a);
    float uvVariation = fwidth(texcoord.x) + fwidth(texcoord.y);

    vec4 tex = texture(gtexture, texcoord);

    //---------------------------------------------------------------- nametags
#ifdef PROGRAM_ENTITIES_TRANSLUCENT
    // Texto flotante (ShaderKey TEXT / TEXT_BG): glifos del atlas de fuentes de 256x256; el fondo es un quad sin UV.
    bool fontAtlas = all(equal(textureSize(gtexture, 0), ivec2(256)));
    bool glyph = fontAtlas && min(tex.r, min(tex.g, tex.b)) > 0.85;
    bool textBg = uvVariation == 0.0 && abs(dot(normalize(worldNormal), normalize(playerPos))) > 0.15;
    if (glyph || textBg) {
        vec4 c = uvVariation == 0.0 ? vcolor : tex * vcolor;
        // copia al 50 % que atraviesa paredes: opaca detrás de lo opaco
        if (glyph && vcolor.a < 0.99
            && linearDepth(gl_FragCoord.z) > linearDepth(texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r) + 0.05) {
            c.a = tex.a;
        }
        if (c.a < 0.004) discard;
        vec3 col = toLinear(c.rgb) * 1.3;   // brillo fijo
        float textCover = c.a > 0.5 ? 1.0 : 0.0;
        outColor = vec4(col, c.a);
        outData = vec4(encodeNormal(vec3(0.0, 1.0, 0.0)), encodeMaterial(MAT_TEXT), textCover);
        outEdge = vec4(0.0, 0.0, 0.0, textCover);
        outPbr = vec4(0.0, 0.0, 0.0, textCover);
        return;
    }
#endif

#if defined PROGRAM_TERRAIN && defined PORTAL_EMISSIVE
    // ---------------------------------------------------------------- portal del Nether
    // va en layer.solid (block.properties) para que el agua y el cristal lo refracten
    if (blockId == 14) {
        outColor = vec4(portalEmission(tex.rgb * vcolor.rgb), 1.0);
        outData = vec4(encodeNormal(normalize(worldNormal)), encodeMaterial(MAT_PORTAL), 1.0);
        outEdge = vec4(0.0, 0.0, 0.0, 1.0);
        outPbr = vec4(0.0, 0.0, lmcoord.y, 1.0);
        return;
    }
#endif

    //---------------------------------------------------------------- albedo
    vec4 albedo;
    float vao = 1.0;
#ifdef PROGRAM_TERRAIN
    albedo = vec4(tex.rgb * vcolor.rgb, tex.a);
    vao = vcolor.a;   // AO vanilla en el alfa (separateAo)
    // umbral de vanilla
    if (albedo.a < 0.5) discard;
#else
    albedo = tex * vcolor;
    if (albedo.a < 0.1) discard;
#endif

#ifdef ENTITY_LIKE
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
#endif
    albedo.rgb = saturateColor(toLinear(albedo.rgb), ALBEDO_SATURATION);

#if defined ENTITY_LIKE && defined XP_ORB_GLOW
    // ---------------------------------------------------------------- orbes de experiencia
    if (entityKind == ENTITY_XP_ORB) {
        float a = saturate(albedo.a * 1.8);
        float orbCover = a > 0.5 ? 1.0 : 0.0;
        outColor = vec4(albedo.rgb * XP_ORB_BRIGHTNESS, a);
        outData = vec4(encodeNormal(normalize(worldNormal)), encodeMaterial(MAT_ENTITY), orbCover);
        outEdge = vec4(0.0, 0.0, 0.0, orbCover);
        outPbr = vec4(0.0, 0.04, lmcoord.y, orbCover);
        return;
    }
#endif

    //---------------------------------------------------------------- material
    int id = blockId;
    int mat = MAT_TERRAIN;
#if defined PROGRAM_HAND
    mat = MAT_HAND;
#elif defined ENTITY_LIKE
    mat = MAT_ENTITY;
#elif defined PROGRAM_BLOCK
    mat = MAT_BLOCKENTITY;
#endif

    float smoothness = 0.5;
    float metal = 0.0;
    float f0 = 0.04;
    float emission = 0.0;
    float sss = 0.0;
#ifdef ENTITY_LIKE
    // cristales del End; los rayos de curación (textura pequeña) algo menos
    if (entityKind == ENTITY_END_CRYSTAL) {
        albedo.rgb = mix(albedo.rgb, END_CRYSTAL_LIGHT * max(max3(albedo.rgb), 0.5), 0.75);
        emission = 1.3;
    } else if (entityKind == ENTITY_ENDER_DRAGON && textureSize(gtexture, 0).x < 128) {
        albedo.rgb = mix(albedo.rgb, END_CRYSTAL_LIGHT * max(max3(albedo.rgb), 0.5), 0.6);
        emission = 0.8;
    }
#endif

#ifdef PROGRAM_TERRAIN
    if (idIsPlant(id)) {
        mat = MAT_FOLIAGE;
        sss = id == 4 ? 0.6 : 1.0;
        smoothness *= 0.6;
        // capa de luciérnagas (luz 15 del modelo)
        if (id == 9 && lmcoord.x > 0.98) emission = 1.0;
    } else if (id == 15) {
        mat = MAT_LAVA;
        emission = 0.75 + 0.5 * luminance(albedo.rgb);
        smoothness = 0.2;
    } else if (idIsEmitter(id)) {
        mat = MAT_EMISSIVE;
        // fuego del End: morado
        if (id == 62 && isEnd()) albedo.rgb = END_CRYSTAL_LIGHT * max3(albedo.rgb);
        // sólo los píxeles claros
        emission = smoothstep(0.35, 0.80, max3(albedo.rgb));
    } else if (id == 70) {
        mat = MAT_METAL;
        smoothness = 0.85;
        metal = 0.5;
    }
#endif
#ifdef SSS_ALL_BLOCKS
    #if defined LEAF_SSS && (defined PROGRAM_TERRAIN || defined PROGRAM_BLOCK)
    // SSS_ALL_BLOCKS: todos los bloques con la luz de las hojas
    if (sss <= 0.0 && emission <= 0.0 && mat != MAT_LAVA) sss = 1.0;
    #endif
#endif

    //---------------------------------------------------------------- PBR
    vec3 ng = normalize(worldNormal);
    vec3 N = ng;
    float pbrAO = 1.0;

#ifdef PBR_NORMALS
    vec4 nt = texture(normals, texcoord);
    vec2 nxy = nt.xy * 2.0 - 1.0;
    bool hasNormalMap = dot(nxy, nxy) > 1e-5 && !(nt.b == 0.0 && nt.a == 0.0) && dot(worldTangent.xyz, worldTangent.xyz) > 0.25;
    if (hasNormalMap) {
        nxy *= NORMAL_STRENGTH;
        vec3 T = normalize(worldTangent.xyz - ng * dot(ng, worldTangent.xyz));
        vec3 B = cross(T, ng) * (worldTangent.w < 0.0 ? -1.0 : 1.0);
        float nz = sqrt(saturate(1.0 - dot(nxy, nxy)));
        N = normalize(T * nxy.x + B * nxy.y + ng * nz);
        pbrAO = nt.b;
    }
#endif

#ifdef PBR_SPECULAR
    vec4 sp = texture(specular, texcoord);
    smoothness = max(smoothness, sp.r);
    if (sp.g > 229.5 / 255.0) {
        metal = 1.0;
    } else if (sp.g > 0.0) {
        f0 = sp.g;
    }
    #ifdef PBR_EMISSIVE
    if (sp.a < 0.999) emission = max(emission, sp.a * textureGlowScale(id));
    #endif
#endif

    //---------------------------------------------------------------- ajuste a texel
    vec2 st = texelSnapOffset(uvT, dTdx, dTdy);
    vec3 posSnap = playerPos + dPdx * st.x + dPdy * st.y;

    vec3 posLight = posSnap;
    vec2 lm = saturate(lmcoord + dLdx * st.x + dLdy * st.y);
    float ao = saturate(vao + dAdx * st.x + dAdy * st.y);

#ifndef VANILLA_AO
    ao = 1.0;
#endif

    // sombras en la rejilla de texels; hojas y plantas sin rejilla
    vec3 posShadow = sss > 0.0 ? playerPos : posSnap;

#ifdef RAIN_PUDDLES
#ifdef PROGRAM_TERRAIN
    //---------------------------------------------------------------- lluvia: mojado y charcos
    if ((mat == MAT_TERRAIN || mat == MAT_METAL) && wetness > 0.001 && overworldSky()) {
        float wet = wetness * rainExposure(posSnap, lm.y);
        if (wet > 0.001) {
            albedo.rgb *= 1.0 - 0.22 * wet;
            smoothness = mix(smoothness, max(smoothness, 0.78), wet);
            if (ng.y > 0.9) {
                // rejilla propia
                vec3 wq = playerPos + cameraPositionFract + vec3(cameraPositionInt & ivec3(1023));
                vec2 cell = (floor(wq.xz * float(PUDDLE_PIXELS)) + 0.5) / float(PUDDLE_PIXELS);
                float coverage = float(PUDDLE_COVERAGE) / 100.0 * wet;
                if (isPuddle(cell, coverage)) {
                    mat = MAT_PUDDLE;
                    smoothness = 0.96;
                    albedo.rgb = albedo.rgb * 0.60 + vec3(0.010, 0.020, 0.030);
                    N = ng;
                    // borde del charco
                    float e = 1.0 / float(PUDDLE_PIXELS);
                    bool rim = !isPuddle(cell + vec2(e, 0.0), coverage) || !isPuddle(cell - vec2(e, 0.0), coverage)
                            || !isPuddle(cell + vec2(0.0, e), coverage) || !isPuddle(cell - vec2(0.0, e), coverage);
                    if (rim) albedo.rgb *= 1.45;
    #ifdef RAIN_RIPPLES
                    vec2 slope;
                    float ring = rainRipples(cell, frameTimeCounter, rainStrength * 0.9, slope);
                    N = normalize(vec3(-slope.x, 1.0, -slope.y));
                    albedo.rgb += vec3(0.10, 0.12, 0.14) * ring;
    #endif
                }
            }
        }
    }
#endif
#endif

#ifdef WHITE_WORLD
    // WHITE_WORLD
    if (emission <= 0.0) albedo.rgb = WHITE_ALBEDO;
#endif

    //---------------------------------------------------------------- iluminación
    LitOut lit = shadeToon(albedo.rgb, N, ng, posLight, posShadow, lm, ao * pbrAO,
                           smoothness, metal, emission, sss);
    vec3 color = lit.color;
#ifdef PLAYER_STUDIO_LIGHT
    #ifdef ENTITY_LIKE
    if (entityKind == ENTITY_PLAYER) color += studioReflection(N, playerPos, lm);
    #endif
#endif

    float cover = albedo.a > 0.5 ? 1.0 : 0.0;
#ifdef PROGRAM_TERRAIN
    if (mat != MAT_FOLIAGE) {
        vec4 mark = lightMeterMark(playerPos, ng, lmcoord, dPdx, dPdy, dLdx, dLdy);
        color = mix(color, mark.rgb, mark.a);
    }
#endif
    outColor = vec4(color, albedo.a);
#ifdef HIDES_PARTICLES
    outHideParticles = vec4(0.0, 0.0, 0.0, cover);
#endif
    // normal con ondas para el reflejo
    outData = vec4(encodeNormal(mat == MAT_PUDDLE ? N : ng), encodeMaterial(mat, lm.x), cover);
    outEdge = vec4(lit.edgeLight, cover);
    outPbr = vec4(smoothness, metal > 0.5 ? 1.0 : f0, lm.y, cover);
}

#endif
