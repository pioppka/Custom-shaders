// Partículas y clima, a la capa translúcida (colortex5)

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

// frame de impacto: buscan explosiones
#if defined IMPACT_FRAMES && !defined PROGRAM_WEATHER && !defined PROGRAM_PARTICLES_TRANSLUCENT
    #define IMPACT_DETECT
#endif

//==============================================================================
#ifdef VERTEX_SHADER

out vec2 texcoord;
out vec2 lmcoord;
out vec4 vcolor;
out vec3 playerPos;
#ifdef IMPACT_DETECT
out vec2 quadCorner;
#endif

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(gl_MultiTexCoord1.xy / 240.0);
    vcolor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = viewToPlayer(viewPos.xyz);
    gl_Position = gl_ProjectionMatrix * viewPos;
#ifdef IMPACT_DETECT
    // esquina del quad (4 vértices seguidos por partícula)
    quadCorner = vec2[4](vec2(1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0), vec2(-1.0, -1.0))[gl_VertexID & 3];
#endif
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

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 vcolor;
in vec3 playerPos;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outTrans;

// Lluvia y sus salpicaduras: texturas azules de vanilla (la nieve es blanca). Se pintan de celeste.
const vec3 RAIN_COLOR = vec3(0.06, 0.48, 1.00);   // ≈ #46B9FF
bool rainTexel(vec3 t) { return t.b > 0.6 && t.b > t.r * 1.8 && t.b > t.g * 1.4; }

#ifdef IMPACT_DETECT
#include "/lib/state.glsl"

in vec2 quadCorner;

// Partículas de explosión: luz 15, gris claro, quad de 2-4 bloques con sprite blanco de 32 px. Tamaños desde las
// derivadas respecto a la esquina (posición y UV son afines en quadCorner). Una muestra cada 8x8 píxeles con posición
// y distancia; aparte, las casi blancas.
void markExplosion(vec4 tex, mat2 dCorner, mat2 dUv, mat2x3 dPos) {
    if (any(notEqual(ivec2(gl_FragCoord.xy) & 7, ivec2(0)))) return;
    if (lmcoord.x < 0.99 || lmcoord.y < 0.99 || tex.a < 0.5 || min3(vcolor.rgb) < 0.35) return;
    if (abs(vcolor.r - vcolor.g) > 0.01 || abs(vcolor.g - vcolor.b) > 0.01) return;
    if (max3(tex.rgb) < 0.4 || max3(tex.rgb) - min3(tex.rgb) > 0.15 * max3(tex.rgb)) return;
    if (abs(determinant(dCorner)) < 1e-12) return;
    mat2 toCorner = inverse(dCorner);
    float widthBlocks = 2.0 * length((dPos * toCorner)[0]);
    float spritePx = 2.0 * length((dUv * toCorner)[0] * vec2(textureSize(gtexture, 0)));
    if (widthBlocks < 1.8 || spritePx < 24.0) return;
    if (min3(tex.rgb) < 0.99) {
        atomicAdd(mrState.impactSeen[5], 1);
        return;
    }
    ivec3 q = ivec3(round(playerPos * 4.0));
    atomicAdd(mrState.impactSeen[0], 1);
    atomicAdd(mrState.impactSeen[1], q.x);
    atomicAdd(mrState.impactSeen[2], q.y);
    atomicAdd(mrState.impactSeen[3], q.z);
    atomicMax(mrState.impactSeen[4], 10000 - int(min(length(playerPos), 99.0) * 100.0));
}
#endif

void main() {
#ifdef IMPACT_DETECT
    mat2 dCorner = mat2(dFdx(quadCorner), dFdy(quadCorner));
    mat2 dUv = mat2(dFdx(texcoord), dFdy(texcoord));
    mat2x3 dPos = mat2x3(dFdx(playerPos), dFdy(playerPos));
#endif
    vec4 tex = texture(gtexture, texcoord);
    vec4 c = tex * vcolor;
    if (c.a < 0.004) discard;
#ifdef IMPACT_DETECT
    markExplosion(tex, dCorner, dUv, dPos);
#endif
    vec3 albedo = toLinear(c.rgb);

#ifdef PROGRAM_WEATHER
    vec3 light = ambientSkyLight() * 1.5 + celestialLightColor() * 0.3 + vec3(0.04);
    vec3 col = albedo * light;
    float a = c.a * 0.55;
    if (rainTexel(tex.rgb)) {
        col = RAIN_COLOR * (luminance(light) * 1.2);
        a = c.a * 0.70;
    }
    outTrans = vec4(col * a, a);
#else
    if (rainTexel(tex.rgb)) albedo = RAIN_COLOR;
    vec3 blDir;
    vec3 bl = getBlockLight(playerPos, vec3(0.0, 1.0, 0.0), lmcoord.x, blDir);
    vec3 amb = overworldSky() ? ambientSkyLight() * (lmcoord.y * lmcoord.y * 0.85 + lmcoord.y * 0.15) : ambientSkyLight();
    vec3 sun = celestialLightColor() * 0.75 * mainLightFade(lmcoord.y);
    bl = limitBlockLight(bl, amb + sun, lmcoord.y);
    vec3 col = albedo * (amb + sun + bl + vec3(0.10) * MIN_LIGHT);
    // fuego y lava: brillan
    if (lmcoord.x > 0.97 && luminance(albedo) > 0.2) col = albedo * EMISSIVE_BRIGHTNESS * 0.8;
    outTrans = vec4(col * c.a, c.a);
#endif
}

#endif
