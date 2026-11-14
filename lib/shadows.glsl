#ifndef MRPIXEL_SHADOWS
#define MRPIXEL_SHADOWS

// Mapa de sombras en dos zonas uniformes: ±SHADOW_INNER bloques en la mitad central (16 texels por bloque a 2048) y
// hasta shadowDistance en el resto. El texel exterior es un múltiplo entero del interior (distancias múltiplo de 32).
// Rejilla anclada a un punto del mundo junto al jugador (mrState), que final va moviendo sin cambiar la rejilla.
// Profundidad x0.25.
#include "/lib/state.glsl"

const float SHADOW_INNER = 32.0;

float shadowTexelInner() { return 4.0 * SHADOW_INNER / float(shadowMapResolution); }
float shadowTexelOuter() { return 4.0 * (shadowDistance - SHADOW_INNER) / float(shadowMapResolution); }

// Ancla de mrState en el espacio del jugador
vec3 shadowAnchorPlayer() {
    ivec3 ai = ivec3(mrState.shadowAnchorInt[0], mrState.shadowAnchorInt[1], mrState.shadowAnchorInt[2]);
    vec3 af = vec3(mrState.shadowAnchorFract[0], mrState.shadowAnchorFract[1], mrState.shadowAnchorFract[2]);
    return vec3(ai - cameraPositionInt) + (af - cameraPositionFract);
}

// Centro del mapa en la vista de la luz: la cámara en la rejilla gruesa que pasa por el ancla
vec2 shadowAnchor() {
    float t1 = shadowTexelOuter();
    vec2 cam = shadowModelView[3].xy;
    vec2 o = mrState.shadowAnchorInt[3] != 0 ? (shadowModelView * vec4(shadowAnchorPlayer(), 1.0)).xy : cam;
    return o + floor((cam - o) / t1 + 0.5) * t1;
}

// Fin del frame: con la cámara a más de un bloque del ancla, el ancla pasa al punto de la misma rejilla más cercano
void updateShadowAnchor() {
    vec3 a = shadowAnchorPlayer();
    bool valid = mrState.shadowAnchorInt[3] != 0;
    if (valid && length(a) <= 1.0) return;
    vec3 k = -a;   // de ancla a cámara
    if (valid && length(a) < 256.0) {
        float t1 = shadowTexelOuter();
        vec3 lo = mat3(shadowModelView) * -a;
        k = transpose(mat3(shadowModelView)) * vec3(floor(lo.xy / t1 + 0.5) * t1, lo.z);
    }
    vec3 v = cameraPositionFract + a + k;
    ivec3 vi = ivec3(floor(v));
    for (int i = 0; i < 3; i++) {
        mrState.shadowAnchorInt[i] = cameraPositionInt[i] + vi[i];
        mrState.shadowAnchorFract[i] = v[i] - float(vi[i]);
    }
    mrState.shadowAnchorInt[3] = 1;
}

// bloques respecto al ancla -> -1..1, y al revés
vec2 shadowWarp(vec2 u) {
    vec2 a = abs(u);
    vec2 inner = a * (0.5 / SHADOW_INNER);
    vec2 outer = 0.5 + (a - SHADOW_INNER) * (0.5 / (shadowDistance - SHADOW_INNER));
    return sign(u) * mix(inner, outer, step(SHADOW_INNER, a));
}

vec2 shadowUnwarp(vec2 m) {
    vec2 a = abs(m);
    vec2 inner = a * (2.0 * SHADOW_INNER);
    vec2 outer = SHADOW_INNER + (a - 0.5) * (2.0 * (shadowDistance - SHADOW_INNER));
    return sign(m) * mix(inner, outer, step(0.5, a));
}

// Posición en el mapa (-1..1) desde la vista de la luz
vec3 shadowClipFromView(vec3 lv, vec2 anchor) {
    return vec3(shadowWarp(lv.xy - anchor), (shadowProjection[2].z * lv.z + shadowProjection[3].z) * 0.25);
}

// Texel (bloques) en lv; junto al borde entre zonas, el grueso
float shadowTexelAt(vec3 lv, vec2 anchor) {
    vec2 u = abs(lv.xy - anchor);
    return max(u.x, u.y) < SHADOW_INNER - 1.0 ? shadowTexelInner() : shadowTexelOuter();
}

#ifdef SHADOW_SAMPLING

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

// Un texel, sin filtro
float shadowTest(sampler2D tex, vec3 s) {
    ivec2 i = clamp(ivec2(s.xy * float(shadowMapResolution)), ivec2(0), ivec2(shadowMapResolution - 1));
    return step(s.z, texelFetch(tex, i, 0).r);
}

// Coordenadas en el mapa de pos (desplazado 1.5 texels por la normal) y desvanecimiento. false fuera del mapa
bool shadowCoords(vec3 pos, vec3 geoNormal, out vec3 s, out float fade) {
    s = vec3(0.0);
    fade = smoothstep(shadowDistance * 0.80, shadowDistance * 0.97, length(pos));
    if (fade >= 1.0) return false;
    vec2 anchor = shadowAnchor();
    float texel = shadowTexelAt((shadowModelView * vec4(pos, 1.0)).xyz, anchor);
    s = shadowClipFromView((shadowModelView * vec4(pos + geoNormal * (texel * 1.5 + 0.02), 1.0)).xyz, anchor) * 0.5 + 0.5;
    if (any(lessThan(s, vec3(0.0))) || any(greaterThan(s, vec3(1.0)))) return false;
    s.z -= 0.00005;
    return true;
}

// Tinte del cristal de color delante de s
vec3 shadowGlassTint(vec3 s, float opaque) {
#ifdef COLORED_SHADOWS
    if (opaque > 0.001) {
        float all0 = shadowTest(shadowtex0, s);
        if (all0 < opaque - 0.001) {
            vec4 cs = texelFetch(shadowcolor0, clamp(ivec2(s.xy * float(shadowMapResolution)), ivec2(0), ivec2(shadowMapResolution - 1)), 0);
            vec3 tint = mix(vec3(1.0), saturateColor(toLinear(cs.rgb), 1.3), saturate(cs.a));
            return mix(vec3(1.0), tint, (opaque - all0) / opaque);
        }
    }
#endif
    return vec3(1.0);
}

// Sombra del mapa en s, con el tinte del cristal de color que haya delante
vec3 shadowFromMap(vec3 s) {
    float opaque = shadowTest(shadowtex1, s);
    return opaque * shadowGlassTint(s, opaque);
}

// Inversa de shadowClipFromView: punto del texel uv a profundidad z (espacio jugador)
vec3 shadowTexelPlayer(vec2 uv, float z) {
    vec3 d = vec3(uv, z) * 2.0 - 1.0;
    vec3 lv = vec3(shadowUnwarp(d.xy) + shadowAnchor(), (d.z * 4.0 - shadowProjection[3].z) / shadowProjection[2].z);
    return (shadowModelViewInverse * vec4(lv, 1.0)).xyz;
}

// pos: espacio jugador; geoNormal: normal geométrica
vec3 getShadow(vec3 pos, vec3 geoNormal) {
#ifndef SHADOWS
    return vec3(1.0);
#else
    vec3 s;
    float fade;
    if (!shadowCoords(pos, geoNormal, s, fade)) return vec3(1.0);
    return mix(shadowFromMap(s), vec3(1.0), fade);
#endif
}

// Transmitancia por t bloques de hojas
float leafTransmit(float t) { return 0.7 * exp(-1.2 * t) + 0.3 * exp(-0.3 * t); }
vec4 leafTransmit(vec4 t) { return 0.7 * exp(-1.2 * t) + 0.3 * exp(-0.3 * t); }

// Luz a través de las hojas según el grosor hasta lo primero que tapa; desde ~5 bloques, sombra. 12 muestras, radio r
float getShadowThrough(vec3 pos, vec3 geoNormal, vec3 L, float r) {
#ifndef SHADOWS
    return 1.0;
#else
    float fade = smoothstep(shadowDistance * 0.80, shadowDistance * 0.97, length(pos));
    if (fade >= 1.0) return 1.0;
    vec3 t = normalize(cross(L, abs(L.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(L, t);
    vec2 anchor = shadowAnchor();
    float texel = shadowTexelAt((shadowModelView * vec4(pos, 1.0)).xyz, anchor);
    vec3 biased = pos + geoNormal * (texel * 1.5 + 0.02);
    float res = float(shadowMapResolution);
    float perBlock = 0.125 * abs(shadowProjection[2].z);   // profundidad del mapa por bloque
    float sum = 0.0;
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 2.3999632;
        vec3 sp = biased + (t * cos(ang) + b * sin(ang)) * (r * sqrt((float(i) + 0.5) / 12.0));
        vec3 s = shadowClipFromView((shadowModelView * vec4(sp, 1.0)).xyz, anchor) * 0.5 + 0.5;
        if (any(lessThan(s, vec3(0.0))) || any(greaterThan(s, vec3(1.0)))) {
            sum += 1.0;
            continue;
        }
        vec2 tc = s.xy * res - 0.5;
        vec2 c0 = floor(tc);
        vec2 f = tc - c0;
        vec4 thick = max(vec4(s.z - 0.00005) - textureGather(shadowtex1, (c0 + 1.0) / res), 0.0) / perBlock;
        vec4 tr = leafTransmit(thick) * (1.0 - smoothstep(4.0, 6.0, thick));
        sum += mix(mix(tr.w, tr.z, f.x), mix(tr.x, tr.y, f.x), f.y);
    }
    return mix(sum / 12.0, 1.0, fade);
#endif
}

// Sombra suave para hojas: 12 muestras en un disco de radio r, PCF bilineal
vec3 getShadowSoft(vec3 pos, vec3 geoNormal, vec3 L, float r) {
#ifndef SHADOWS
    return vec3(1.0);
#else
    float fade = smoothstep(shadowDistance * 0.80, shadowDistance * 0.97, length(pos));
    if (fade >= 1.0) return vec3(1.0);
    vec3 t = normalize(cross(L, abs(L.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(L, t);
    vec2 anchor = shadowAnchor();
    float texel = shadowTexelAt((shadowModelView * vec4(pos, 1.0)).xyz, anchor);
    vec3 biased = pos + geoNormal * (texel * 1.5 + 0.02);
    float res = float(shadowMapResolution);
    float sum = 0.0;
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 2.3999632;   // ángulo áureo
        vec3 sp = biased + (t * cos(ang) + b * sin(ang)) * (r * sqrt((float(i) + 0.5) / 12.0));
        vec3 s = shadowClipFromView((shadowModelView * vec4(sp, 1.0)).xyz, anchor) * 0.5 + 0.5;
        if (any(lessThan(s, vec3(0.0))) || any(greaterThan(s, vec3(1.0)))) {
            sum += 1.0;
            continue;
        }
        vec2 tc = s.xy * res - 0.5;
        vec2 c0 = floor(tc);
        vec2 f = tc - c0;
        // los 4 texeles del bilineal en una lectura: w (0,0), z (1,0), x (0,1), y (1,1)
        vec4 lit = step(vec4(s.z - 0.00005), textureGather(shadowtex1, (c0 + 1.0) / res));
        sum += mix(mix(lit.w, lit.z, f.x), mix(lit.x, lit.y, f.x), f.y);
    }
    return mix(vec3(sum / 12.0), vec3(1.0), fade);
#endif
}

#endif // SHADOW_SAMPLING

#endif
