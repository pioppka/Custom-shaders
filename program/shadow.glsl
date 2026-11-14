// Pase de sombras: mapa de sombras y voxelización del terreno cercano (floodfill, reflejos, niebla de suelo)

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

#include "/lib/waving.glsl"

in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_midBlock;

uniform sampler2D gtexture;

#ifdef FLOODFILL
layout(r32ui) uniform uimage3D voxelImg;
    #if PBR_GLOW_LIGHT > 0
        #define PBR_GLOW
        #if defined PBR_SPECULAR && defined PBR_EMISSIVE
uniform sampler2D specular;
        #endif
    #endif
    #ifdef GROUND_FOG
#include "/lib/groundfog.glsl"
layout(r32ui) uniform uimage3D fogPushImg;   // bloques que tocan entidades
    #endif
#endif

#ifdef WATER_SIM
#include "/lib/watersim.glsl"
layout(r32ui) uniform uimage2D waveImpulseImg;
#endif

#if defined WATER_FOAM && !defined FLOODFILL
// Orilla sin floodfill: 1 agua, 2 geometría, 4 bloque entero; 64x32x64, bloque del mundo & (63, 31, 63)
layout(r32ui) uniform uimage3D shoreImg;

void markShore(vec3 playerPos, int id) {
    ivec3 b = ivec3(floor(playerPos + at_midBlock.xyz / 64.0 + cameraPositionFract));
    if (abs(b.x) > 30 || abs(b.y) > 14 || abs(b.z) > 30) return;
    uint bits = 1u;
    if (id != 10) {
        vec3 local = -at_midBlock.xyz / 64.0;
        bits = all(greaterThan(abs(local), vec3(0.49))) && idCanBeSolid(id) ? 6u : 2u;
    }
    imageAtomicOr(shoreImg, (b + cameraPositionInt) & ivec3(63, 31, 63), bits);
}
#endif

uniform int entityId;

out vec2 texcoord;
out vec4 vcolor;
flat out int blockId;
flat out int facesMainCamera;
flat out int noShadow;
out vec3 shadowPlayerPos;
out float lmBlock;

#ifdef FLOODFILL
void voxelize(vec3 playerPos, int id) {
    vec3 center = playerPos + at_midBlock.xyz / 64.0;
    ivec3 v = ivec3(floor(center + cameraPositionFract)) + VOXEL_HALF;
    if (!inVoxelVolume(v)) return;

    // vértice en una esquina: probablemente un cubo
    vec3 local = -at_midBlock.xyz / 64.0;
    bool corner = all(greaterThan(abs(local), vec3(0.49)));

    uint data = VOX_GEOMETRY;
    if (id == 10) {
        data = VOX_WATER;
    } else {
        if (corner && idCanBeSolid(id)) data |= VOX_SOLID;
        if (idCanBeSolid(id)) {
            // alfombra, placa de presión, nieve
            bool lowFlat = abs(local.x) > 0.49 && abs(local.z) > 0.49 && local.y < -0.3;
            if (!corner && !lowFlat) data |= VOX_PARTIAL;
            // cara hacia dentro: capa pegada a otro bloque
            if (lowFlat || dot(gl_Normal, local) < -0.2) data |= VOX_THIN;
        }
        if (id == 4) data |= VOX_LEAVES;
        if (idIsTinted(id)) data |= VOX_TINT;
        int level = int(at_midBlock.w + 0.5);
        if (level <= 0 && idIsEmitter(id)) level = emitterDefaultLevel(id);
        if (level > 0) data |= VOX_EMITTER | (uint(clamp(level, 0, 15)) << 16u);
        data |= uint(id & 255) << 8u;
    }
    imageAtomicOr(voxelImg, v, data);

    if (id != 10) {
        // Textura de la cara para los rayos. Sólo caras enteras: en un quad parcial mc_midTexCoord no es el centro
        // del sprite.
        vec2 atlasSize = vec2(textureSize(gtexture, 0));
        vec2 halfT = abs(texcoord - mc_midTexCoord.xy) * atlasSize;
        float sizeT = exp2(round(log2(max(2.0 * max(halfT.x, halfT.y), 1.0))));
        vec2 q = mc_midTexCoord.xy;
        vec2 o = vec2(sizeT * 0.25) / atlasSize;
        float cover = (textureLod(gtexture, q, 0.0).a + textureLod(gtexture, q + o, 0.0).a
                     + textureLod(gtexture, q - o, 0.0).a + textureLod(gtexture, q + vec2(o.x, -o.y), 0.0).a
                     + textureLod(gtexture, q + vec2(-o.x, o.y), 0.0).a) * 0.2;
        ivec2 minT = ivec2(floor(q * atlasSize - sizeT * 0.5 + 0.5));
        bool tinted = any(lessThan(gl_Color.rgb, vec3(0.99)));
        vec3 an = abs(gl_Normal);
        bool atCorner = an.y > 0.9 ? (abs(local.x) > 0.49 && abs(local.z) > 0.49)
                      : an.x > 0.9 ? (abs(local.y) > 0.49 && abs(local.z) > 0.49)
                      : an.z > 0.9 ? (abs(local.x) > 0.49 && abs(local.y) > 0.49)
                      : abs(local.y) > 0.49;
        bool fullFace = atCorner && abs(halfT.x - halfT.y) < 0.75;
        if (fullFace && all(greaterThanEqual(minT, ivec2(0))) && all(lessThan(minT, ivec2(8192)))) {
            int face = faceIndex(gl_Normal);
            uint word = packFaceSprite(minT, int(round(log2(sizeT))), tinted, cover > 0.5);
            imageAtomicMax(voxelImg, slotCoord(v, SLOT_FACE + face), word);
            // capa con huecos (pasto): aparte
            if (cover <= 0.5 && face >= 2) imageAtomicMax(voxelImg, slotCoord(v, SLOT_OVERLAY), word);
        }
    #ifdef PBR_GLOW
        // Textura que brilla en un bloque sin luz (menas), una vez por quad: capa emisiva con luz 15, o alfa labPBR <
        // 1.
        if ((data & VOX_EMITTER) == 0u && (gl_VertexID & 3) == 0) {
            float frac = 0.0;
            vec3 ec = vec3(0.0);
            if (gl_MultiTexCoord1.x > 239.0) {
                // rectángulo de UV del quad en 16x16
                vec2 lo = q * atlasSize - halfT;
                for (int i = 0; i < 256; i++) {
                    vec4 c = texelFetch(gtexture, ivec2(lo + (vec2(float(i & 15), float(i >> 4)) + 0.5) * (halfT / 8.0)), 0);
                    if (c.a > 0.5) {
                        frac += 1.0 / 256.0;
                        ec += toLinear(c.rgb);
                    }
                }
            }
        #if defined PBR_SPECULAR && defined PBR_EMISSIVE
            else if (fullFace && all(equal(textureSize(specular, 0), ivec2(atlasSize)))) {
                for (int i = 0; i < 64; i++) {
                    ivec2 tc = minT + ivec2((vec2(float(i & 7), float(i >> 3)) + 0.5) * (sizeT / 8.0));
                    float a = texelFetch(specular, tc, 0).a;
                    if (a > 0.02 && a < 0.999) {
                        frac += a / 64.0;
                        ec += toLinear(texelFetch(gtexture, tc, 0).rgb) * a;
                    }
                }
            }
        #endif
            float glow = float(PBR_GLOW_LIGHT) * min(1.0, 0.4 + frac * 4.0) * textureGlowScale(id);
            if (frac > 0.0 && glow >= 0.5) {
                imageAtomicOr(voxelImg, v, VOX_PBRGLOW);
                imageAtomicMax(voxelImg, slotCoord(v, SLOT_GLOW), packPbrGlow(int(round(glow)), ec / max(max3(ec), 1e-4)));
            }
        }
    #endif
        // atomicMax: tinte estable entre esquinas
        if (tinted) imageAtomicMax(voxelImg, slotCoord(v, SLOT_TINT), packUnorm4x8(vec4(gl_Color.rgb, 1.0)));
    }
}
#endif

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vcolor = gl_Color;
    blockId = int(max(mc_Entity.x, 0.0) + 0.5);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPos = (shadowModelViewInverse * viewPos).xyz;

    // quads de cara a la cámara (nametags)
    vec3 n = gl_NormalMatrix * gl_Normal;
    vec3 wn = dot(n, n) > 1e-8 ? mat3(shadowModelViewInverse) * normalize(n) : vec3(0.0);
    facesMainCamera = abs(dot(wn, gbufferModelViewInverse[2].xyz)) > 0.9995 ? 1 : 0;

    bool isTerrain = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID
                  || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
                  || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
                  || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;

    noShadow = 0;
#ifdef XP_ORB_GLOW
    // orbes de experiencia: sin sombra; con floodfill dan luz
    if (!isTerrain && entityId == ENTITY_XP_ORB) {
        noShadow = 1;
    #ifdef FLOODFILL
        ivec3 xv = ivec3(floor(playerPos + cameraPositionFract)) + VOXEL_HALF;
        if (inVoxelVolume(xv)) imageAtomicOr(voxelImg, xv, VOX_XP);
    #endif
    }
#endif

#ifdef FLOODFILL
    // cristales del End: luz morada
    if (!isTerrain && entityId == ENTITY_END_CRYSTAL) {
        ivec3 cv = ivec3(floor(playerPos + cameraPositionFract)) + VOXEL_HALF;
        if (inVoxelVolume(cv)) imageAtomicOr(voxelImg, cv, VOX_CRYSTAL);
    }
#endif

#if defined FLOODFILL && defined GROUND_FOG
    // niebla de suelo: la apartan las entidades
    if (!isTerrain && facesMainCamera == 0 && renderStage != MC_RENDER_STAGE_BLOCK_ENTITIES) {
        ivec3 fb = gfogBlock(playerPos);
        if (gfogInBlocks(fb)) imageAtomicMax(fogPushImg, fb, 1u);
    }
#endif

#ifdef WATER_SIM
    // olas interactivas: entidades en la superficie
    if (!isTerrain && facesMainCamera == 0) {
        ivec2 sc = simCell(playerPos);
        if (simInWindow(sc)) {
            vec2 surf = waterSurf.cells[simSlot(simIndex(sc))];
            float wy = playerPos.y + cameraPositionFract.y + float(cameraPositionInt.y);
            if (simAge(surf.g) < 60.0 && wy > surf.r - 1.2 && wy < surf.r + 0.6) {
                imageAtomicMax(waveImpulseImg, simIndex(sc), 1u);
            }
        }
    }
#endif

    if (isTerrain) {
#ifdef FLOODFILL
        voxelize(playerPos, blockId);
#endif
#if defined WATER_FOAM && !defined FLOODFILL
        markShore(playerPos, blockId);
#endif
        vec3 wave = wavingOffset(playerPos, blockId, texcoord, mc_midTexCoord.xy);
        if (dot(wave, wave) > 0.0) {
            playerPos += wave;
            viewPos = shadowModelView * vec4(playerPos, 1.0);
        }
    }

    shadowPlayerPos = playerPos;
    lmBlock = gl_MultiTexCoord1.x / 240.0;
    gl_Position = vec4(shadowClipFromView(viewPos.xyz, shadowAnchor()), 1.0);
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 vcolor;
flat in int blockId;
flat in int facesMainCamera;
flat in int noShadow;
in vec3 shadowPlayerPos;
in float lmBlock;

#ifdef FLOODFILL
layout(r32ui) uniform uimage3D voxelImg;
#else
layout(r32ui) uniform uimage2D fireLightImg;
#endif

// Llamas de una entidad que arde: con floodfill se marca su vóxel; sin él, su celda de 2 bloques (fireLightImg)
bool flameTexel(vec3 c) { return max3(c) > 0.55 && c.b < c.r * 0.6; }

void markEntityFire(vec3 pos) {
#ifdef FLOODFILL
    ivec3 v = playerToVoxel(pos);
    if (inVoxelVolume(v)) imageAtomicOr(voxelImg, v, VOX_FIRE);
#else
    ivec3 c = ivec3(floor((pos + cameraPositionFract) * 0.5));   // relativa al bloque de la cámara
    if (any(greaterThan(abs(c), ivec3(120)))) return;
    uvec3 u = uvec3(c + 128);
    int slot = int(((u.x * 73856093u) ^ (u.y * 19349663u) ^ (u.z * 83492791u)) % uint(FIRE_LIGHTS));
    imageAtomicMax(fireLightImg, ivec2(slot, 0), u.x | (u.y << 8u) | (u.z << 16u) | (1u << 24u));
    imageAtomicMax(fireLightImg, ivec2(FIRE_LIGHTS, 0), 1u);
#endif
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor;

void main() {
    vec4 tex = texture(gtexture, texcoord);

    // el texto flotante no proyecta sombra
    bool constUV = fwidth(texcoord.x) + fwidth(texcoord.y) == 0.0;
    bool fontAtlas = all(equal(textureSize(gtexture, 0), ivec2(256)));
    bool entityStage = renderStage == MC_RENDER_STAGE_ENTITIES;
    if (entityStage && (constUV || (fontAtlas && min(tex.r, min(tex.g, tex.b)) > 0.85))) discard;
    if (facesMainCamera == 1 && (constUV || fontAtlas)) discard;
    if (noShadow == 1) discard;

    bool translucent = renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
    bool terrain = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
                || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED;
    if (tex.a < (terrain ? 0.5 : 0.1)) discard;
    if (entityStage && lmBlock > 0.99 && textureSize(gtexture, 0).x >= 512 && flameTexel(tex.rgb)) markEntityFire(shadowPlayerPos);
    if (blockId == 10) discard;
#ifdef PORTAL_EMISSIVE
    if (blockId == 14) discard;
#endif

    outShadowColor = translucent ? vec4(tex.rgb * vcolor.rgb, tex.a) : vec4(1.0);
}

#endif
