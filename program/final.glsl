// Final: glow, destellos, tonemap, color y viñeta

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
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

#include "/lib/sky.glsl"
#include "/lib/shadows.glsl"
#include "/lib/title.glsl"

const bool colortex3MipmapEnabled = true;
const bool colortex0MipmapEnabled = true;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;

in vec2 uv;

layout(location = 0) out vec4 outColor;

#ifdef DOF
// ------------------------------------------------------------------ desenfoque
uniform float centerDepthSmooth;
const float centerDepthHalflife = 0.6;

// Radio en píxeles (0 en el foco); mano y texto nítidos. back: cielo o nubes
float dofRadius(ivec2 q, float focus, float maxPx, out float dist, out bool back) {
    float d = texelFetch(depthtex0, q, 0).r;
    int m = decodeMaterial(texelFetch(colortex1, q, 0).b);
    back = d >= SKY_DEPTH || m == MAT_CLOUD;
    dist = back ? far * 4.0 : linearDepth(d);
    if (back || m == MAT_HAND || m == MAT_TEXT) return 0.0;
    return maxPx * smoothstep(0.05, 0.8, abs(dist - focus) / max(dist, focus));
}

// Una copia a cada lado según el radio, sólo sobre lo de detrás. Cielo y nubes: la copia del objeto q de delante que
// cae aquí (q + radio).
vec3 horizontalDof(ivec2 px, vec3 col) {
    vec2 res = viewSize();
    float maxPx = float(DOF_STRENGTH) * max(res.y / 1080.0, 1.0);
    float focus = centerDepthSmooth >= SKY_DEPTH ? far * 4.0 : linearDepth(centerDepthSmooth);
    float dist;
    bool back;
    float r = dofRadius(px, focus, maxPx, dist, back);
    int o = int(r + 0.5);
    if (o < 1 && !back) return col;
    int xMax = int(res.x) - 1;
    vec3 sum = col * 0.5;
    float wsum = 0.5;
    for (int side = -1; side <= 1; side += 2) {
        ivec2 q = px;
        float ds;
        bool bs;
        float w = 0.0;
        if (back) {
            int k = int(maxPx + 0.5);
            for (int it = 0; it < 2; it++) {
                q = ivec2(clamp(px.x - side * k, 0, xMax), px.y);
                int kq = int(dofRadius(q, focus, maxPx, ds, bs) + 0.5);
                if (bs || kq < 1) break;
                if (abs(kq - k) <= 1) { w = 0.25; break; }
                k = kq;
            }
        } else {
            q = ivec2(clamp(px.x + side * o, 0, xMax), px.y);
            float rs = dofRadius(q, focus, maxPx, ds, bs);
            // lo que queda claramente detrás no se copia encima
            if (!bs && ds <= dist * 1.1 + 0.5) w = 0.25 * (ds < dist ? saturate(rs / r) : 1.0);
        }
        if (w > 0.0) {
            sum += texelFetch(colortex0, q, 0).rgb * w;
            wsum += w;
        }
    }
    return sum / wsum;
}
#endif

// ------------------------------------------------------------------ glow
vec3 pixelBloom() {
    vec2 res = viewSize();
    float scale = max(res.y / 1080.0, 1.0);
#if BLOOM_PIXEL_SIZE > 0
    float P = max(1.0, floor(float(BLOOM_PIXEL_SIZE) * scale + 0.5));
    vec2 cellUV = (floor(gl_FragCoord.xy / P) + 0.5) * P / res;
    float baseLod = max(1.0, floor(log2(P) + 0.5));
#else
    vec2 cellUV = gl_FragCoord.xy / res;
    float baseLod = 1.0;
#endif
    vec3 b = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 6; i++) {
        float w = 1.0 / (1.0 + float(i) * 0.6);
        b += textureLod(colortex3, cellUV, baseLod + float(i)).rgb * w;
        wsum += w;
    }
    b /= wsum;
#if BLOOM_STEPS > 0
    // escalones
    vec3 bn = b / (1.0 + b);
    bn = floor(bn * float(BLOOM_STEPS) + 0.5) / float(BLOOM_STEPS);
    b = bn / max(1.0 - bn, 0.02);
#endif
    return b * 1.8;
}

// ------------------------------------------------------------------ destellos
float flareDisk(vec2 p, vec2 c, float r) {
    return step(length((p - c) * vec2(aspectRatio, 1.0)), r);
}

float flareRing(vec2 p, vec2 c, float r, float w) {
    return step(abs(length((p - c) * vec2(aspectRatio, 1.0)) - r), w);
}

float flareHex(vec2 p, vec2 c, float r) {
    vec2 q = abs((p - c) * vec2(aspectRatio, 1.0));
    return step(max(q.x * 0.866 + q.y * 0.5, q.y), r);
}

vec3 lensFlare() {
    if (!overworldSky() || sunPosition.z >= 0.0) return vec3(0.0);
    vec4 sc = gbufferProjection * vec4(sunPosition, 1.0);
    vec2 sunUV = sc.xy / sc.w * 0.5 + 0.5;

    vec2 res = viewSize();
    float vis = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2 q = sunUV + vec2(float(x), float(y)) * 0.010 * vec2(1.0 / aspectRatio, 1.0);
            if (all(greaterThan(q, vec2(0.0))) && all(lessThan(q, vec2(1.0)))) {
                vis += texelFetch(depthtex0, ivec2(q * res), 0).r >= SKY_DEPTH ? 1.0 : 0.0;
            }
        }
    }
    vis /= 25.0;
    vis *= smoothstep(0.0, 0.15, sunElevation()) * (1.0 - rainStrength);
    vis *= 1.0 - smoothstep(0.45, 0.80, max(abs(sunUV.x - 0.5), abs(sunUV.y - 0.5)));
    if (vis <= 0.001) return vec3(0.0);

    float P = max(1.0, floor(float(FLARE_PIXEL_SIZE) * max(res.y / 1080.0, 1.0) + 0.5));
    vec2 p = (floor(gl_FragCoord.xy / P) + 0.5) * P / res;
    vec2 axis = vec2(0.5) - sunUV;

    vec3 f = vec3(0.0);
    f += flareDisk(p, sunUV + axis * 0.35, 0.022) * vec3(1.00, 0.75, 0.35) * 0.30;
    f += flareRing(p, sunUV + axis * 0.70, 0.045, 0.006) * vec3(0.45, 1.00, 0.55) * 0.35;
    f += flareHex(p, sunUV + axis * 1.05, 0.034) * vec3(0.55, 0.65, 1.00) * 0.30;
    f += flareDisk(p, sunUV + axis * 1.35, 0.060) * vec3(0.85, 0.45, 1.00) * 0.16;
    f += flareHex(p, sunUV + axis * 1.70, 0.020) * vec3(1.00, 0.55, 0.30) * 0.40;
    f += flareRing(p, sunUV + axis * 2.00, 0.110, 0.008) * vec3(0.50, 0.80, 1.00) * 0.18;
    vec2 d = (p - sunUV) * vec2(aspectRatio, 1.0);
    f += vec3(1.00, 0.80, 0.55) * exp(-abs(d.y) * 150.0) * exp(-abs(d.x) * 5.0) * 0.30;

    return f * vis * FLARE_STRENGTH;
}

// ------------------------------------------------------------------ color
// Curva: f(0.25)=0.33 f(0.5)=0.55 f(1)=0.80 f(2)=0.96
vec3 cartoonTonemap(vec3 x) {
    return 1.0 - exp(-max(x, vec3(0.0)) * 1.6);
}

vec3 grade(vec3 linearColor) {
    vec3 s = toSRGB(linearColor);
    s = (s - 0.5) * CONTRAST + 0.5;
    float sat = max3(s) - min3(s);
    float l = luminance(s);
    s = mix(vec3(l), s, SATURATION * (1.0 + (VIBRANCE - 1.0) * (1.0 - saturate(sat))));
    return saturate(s);
}

#ifdef IMPACT_ON
#include "/lib/state.glsl"

// Frame de impacto: blanco y negro con líneas desde la explosión, primero invertido. lumLinear: antes de exposición y
// tonemap. IMPACT_DEBUG: fijo o en bucle desde el centro.
vec3 impactFrame(vec3 s, vec2 uv, float lumLinear) {
    int cur = (frameCounter & 1) == 0 ? 0 : 8;
#if IMPACT_DEBUG == 1
    float t = IMPACT_FLASH + 0.001;
    vec2 c = vec2(0.5);
#elif IMPACT_DEBUG == 2
    float t = mod(frameTimeCounter, IMPACT_DURATION + 1.0);
    if (t > IMPACT_DURATION) return s;
    vec2 c = vec2(0.5);
#else
    float start = mrState.impactState[cur + 1];
    float t = frameTimeCounter + 1.0 - start;
    if (start <= 0.0 || t < 0.0 || t > IMPACT_DURATION) return s;
    // líneas desde la explosión (o el centro si queda detrás)
    vec3 at = vec3(mrState.impactState[cur + 2], mrState.impactState[cur + 3],
                   mrState.impactState[cur + 4]) - cameraPosition;
    vec3 vp = playerToView(at);
    vec2 c = vp.z < 0.0 ? viewToScreen(vp).xy : vec2(0.5);
#endif
    float v = step(mrState.impactState[cur + 5], lumLinear);
#if IMPACT_POLARITY == 0
    if (mrState.impactState[cur + 6] > 0.5) v = 1.0 - v;
#elif IMPACT_POLARITY == 2
    v = 1.0 - v;
#endif

    // más anchas hacia fuera; cambian IMPACT_LINE_RATE veces por segundo
    vec2 d = (uv - c) * vec2(aspectRatio, 1.0);
    float seg = (atan(d.y, d.x) / 6.2831853 + 0.5) * float(IMPACT_LINES);
    float h = hash12(vec2(floor(seg), floor(t * float(IMPACT_LINE_RATE))));
    float r0 = IMPACT_INNER + 0.45 * fract(h * 7.31);
    float width = IMPACT_LINE_WIDTH * saturate((length(d) - r0) / 0.6);
    if (h > 1.0 - float(IMPACT_LINE_CHANCE) / 100.0 && fract(seg) < width) v = 0.0;

    if (t < IMPACT_FLASH) v = 1.0 - v;
#if IMPACT_DEBUG == 1
    return vec3(v);
#else
    return mix(s, vec3(v), 1.0 - smoothstep(IMPACT_DURATION * 0.67, IMPACT_DURATION, t));
#endif
}
#endif

#if DEBUG_VIEW >= 5
uniform sampler2D colortex4;
uniform sampler2D colortex6;

// Colores de la vista de materiales (MAT_*)
const vec3 MATERIAL_COLORS[18] = vec3[18](
    vec3(0.0),               // nada
    vec3(0.55),              // terreno
    vec3(0.20, 0.80, 0.20),  // hojas y plantas
    vec3(0.10, 0.35, 1.00),  // agua
    vec3(0.60, 0.90, 1.00),  // cristal
    vec3(0.85, 0.90, 1.00),  // hielo
    vec3(1.00, 0.55, 0.10),  // entidades
    vec3(1.00, 0.60, 0.75),  // mano
    vec3(1.0),               // texto
    vec3(1.00, 0.95, 0.20),  // emisivos
    vec3(0.60, 0.35, 0.15),  // bloques-entidad
    vec3(0.90, 0.90, 0.60),  // partículas
    vec3(0.75, 0.80, 0.90),  // nubes
    vec3(0.60, 0.20, 1.00),  // portal
    vec3(1.00, 0.25, 0.05),  // lava
    vec3(0.50, 1.00, 0.40),  // slime
    vec3(0.20, 0.90, 0.90),  // metal
    vec3(0.20, 0.25, 0.70)); // charcos

// Vistas de depuración: 5 lightmap, 6 normales, 7 materiales
vec3 debugView(ivec2 px) {
    vec4 g = texelFetch(colortex1, px, 0);
    bool opaque = g.a > 0.5;
#if DEBUG_VIEW == 5
    if (!opaque) return vec3(0.0);
    return vec3(1.0, 0.5, 0.1) * decodeBlockLight(g.b) + vec3(0.1, 0.4, 1.0) * texelFetch(colortex4, px, 0).b;
#else
    vec4 tr = texelFetch(colortex6, px, 0);
    bool front = tr.w < 1.0 && tr.w <= texelFetch(depthtex0, px, 0).r + 1e-6;
    #if DEBUG_VIEW == 6
    if (front) return decodeNormal(tr.xy) * 0.5 + 0.5;
    return opaque ? decodeNormal(g.rg) * 0.5 + 0.5 : vec3(0.0);
    #else
    vec3 c = opaque ? MATERIAL_COLORS[clamp(decodeMaterial(g.b), 0, 17)] : vec3(0.0);
    if (front) c = mix(c, MATERIAL_COLORS[clamp(int(floor(tr.z + 0.001)), 0, 17)], 0.7);
    return c;
    #endif
#endif
}
#endif

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    if (px == ivec2(0)) updateShadowAnchor();   // ancla de sombras para el frame siguiente
    int mat = decodeMaterial(texelFetch(colortex1, px, 0).b);

    vec3 col = texelFetch(colortex0, px, 0).rgb;

    // nametags: sin tonemap ni glow
    if (mat == MAT_TEXT) {
        outColor = vec4(drawTitle(toSRGB(col), gl_FragCoord.xy), 1.0);
        return;
    }
#ifdef DOF
    col = horizontalDof(px, col);
#endif

#ifdef BLOOM
    // cámara empañada
    float fogLens = rainCameraFog();
    col += pixelBloom() * BLOOM_STRENGTH * (1.0 + 1.5 * fogLens);
    if (fogLens > 0.001) {
        vec2 res = viewSize();
        float P = max(1.0, floor(float(max(BLOOM_PIXEL_SIZE, 2)) * max(res.y / 1080.0, 1.0) + 0.5));
        vec2 cellUV = (floor(gl_FragCoord.xy / P) + 0.5) * P / res;
        vec3 veil = textureLod(colortex0, cellUV, 5.0).rgb;
        col = mix(col, veil, saturate(0.22 * fogLens));
    }
#endif
#ifdef LENS_FLARE
    col += lensFlare();
#endif

#ifdef IMPACT_ON
    float impactLum = luminance(col);
#endif
    col *= EXPOSURE * 0.6;   // EXPOSURE 1 = 0.6
    vec3 s = grade(cartoonTonemap(col));

    vec2 c = uv - 0.5;
    s *= 1.0 - VIGNETTE * pow(saturate(length(c * vec2(aspectRatio * 0.75, 1.0)) * 1.25), 2.5);

#ifdef IMPACT_ON
    s = impactFrame(s, uv, impactLum);
#endif
#if DEBUG_VIEW >= 5
    s = debugView(px);
#endif
    outColor = vec4(drawTitle(s, gl_FragCoord.xy), 1.0);
}

#endif
