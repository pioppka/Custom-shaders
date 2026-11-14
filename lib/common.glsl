#ifndef MRPIXEL_COMMON
#define MRPIXEL_COMMON

// Requiere /lib/uniforms.glsl

const float PI = 3.14159265359;

// Hojas y plantas: transmisión difusa
#ifdef LEAF_SSS
const float LEAF_TRANSMIT = clamp(0.25 * LEAF_SSS_STRENGTH, 0.0, 0.9);
#else
const float LEAF_TRANSMIT = 0.0;
#endif

#if defined IMPACT_FRAMES || IMPACT_DEBUG > 0
    #define IMPACT_ON
#endif

// Depuración: DEBUG_VIEW 1-4 dejan una sola luz (x sol, y cielo, z bloques, w hojas y contraluz)
#if DEBUG_VIEW == 1
const vec4 DEBUG_LIGHTS = vec4(1.0, 0.0, 0.0, 0.0);
#elif DEBUG_VIEW == 2
const vec4 DEBUG_LIGHTS = vec4(0.0, 1.0, 0.0, 0.0);
#elif DEBUG_VIEW == 3
const vec4 DEBUG_LIGHTS = vec4(0.0, 0.0, 1.0, 0.0);
#elif DEBUG_VIEW == 4
const vec4 DEBUG_LIGHTS = vec4(0.0, 0.0, 0.0, 1.0);
#else
const vec4 DEBUG_LIGHTS = vec4(1.0);
#endif

#ifdef WHITE_WORLD
const vec3 WHITE_ALBEDO = vec3(0.6);
#endif

// End: sin techo, luz ambiente 0.25
bool isEnd() { return !hasCeiling && (!hasSkylight || ambientLight > 0.2); }

// Profundidad del cielo (sin reverse-Z en Iris)
const float SKY_DEPTH = 0.99999;

// IDs de entity.properties
#define ENTITY_XP_ORB 100
#define ENTITY_END_CRYSTAL 101
#define ENTITY_ENDER_DRAGON 102
#define ENTITY_PLAYER 103

// Materiales de los G-buffers
#define MAT_NONE 0
#define MAT_TERRAIN 1
#define MAT_FOLIAGE 2
#define MAT_WATER 3
#define MAT_GLASS 4
#define MAT_ICE 5
#define MAT_ENTITY 6
#define MAT_HAND 7
#define MAT_TEXT 8
#define MAT_EMISSIVE 9
#define MAT_BLOCKENTITY 10
#define MAT_PARTICLE 11
#define MAT_CLOUD 12
#define MAT_PORTAL 13
#define MAT_LAVA 14
#define MAT_SLIME 15
#define MAT_METAL 16
#define MAT_PUDDLE 17

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 saturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }

float max3(vec3 v) { return max(v.x, max(v.y, v.z)); }
float min3(vec3 v) { return min(v.x, min(v.y, v.z)); }

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 toSRGB(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }

vec3 saturateColor(vec3 c, float amount) {
    float l = luminance(c);
    return max(mix(vec3(l), c, amount), vec3(0.0));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Normales en octaedro (0..1)
vec2 encodeNormal(vec3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    vec2 e = n.xy;
    if (n.z < 0.0) {
        e = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
    }
    return e * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    float t = max(-n.z, 0.0);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;
    return normalize(n);
}

float encodeMaterial(int id) { return float(id) / 255.0; }
// con la luz de bloque del lightmap en la parte fraccionaria
float encodeMaterial(int id, float lmBlock) { return (float(id) + saturate(lmBlock) * 0.99) / 255.0; }
int decodeMaterial(float v) { return int(v * 255.0 + 0.002); }
float decodeBlockLight(float v) { return fract(v * 255.0 + 0.002) / 0.99; }

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

vec3 screenToView(vec2 uv, float depth) {
    return projectAndDivide(gbufferProjectionInverse, vec3(uv, depth) * 2.0 - 1.0);
}

vec3 viewToScreen(vec3 viewPos) {
    return projectAndDivide(gbufferProjection, viewPos) * 0.5 + 0.5;
}

vec3 viewToPlayer(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
}

vec3 playerToView(vec3 playerPos) {
    return mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;
}

// Distancia lineal desde el depth buffer (proyección real: el plano lejano es ~4x far)
float linearDepth(float d) {
    return gbufferProjection[3].z / ((d * 2.0 - 1.0) + gbufferProjection[2].z);
}

vec2 viewSize() { return vec2(viewWidth, viewHeight); }

// Portal del Nether emisivo
vec3 portalEmission(vec3 texColor) {
    vec3 c = saturateColor(toLinear(texColor), 1.25);
    float pulse = 0.85 + 0.15 * sin(frameTimeCounter * 2.0);
    return (c * (0.6 + 0.8 * luminance(c)) + vec3(0.10, 0.015, 0.22)) * PORTAL_BRIGHTNESS * pulse;
}

// Peso del reflejo plástico por material
float plasticReflectAmount(int mat) {
    if (mat == MAT_TERRAIN || mat == MAT_EMISSIVE || mat == MAT_BLOCKENTITY) return 1.0;
    if (mat == MAT_FOLIAGE) return 0.35;
    return 0.0;
}

// Cámara empañada con lluvia al aire libre
float rainCameraFog() {
    if (isEyeInWater != 0) return 0.0;
    float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    return rainStrength * smoothstep(0.55, 0.9, eyeSky) * RAIN_CAMERA_FOG;
}

#endif
