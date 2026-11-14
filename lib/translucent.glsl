#ifndef MRPIXEL_TRANSLUCENT
#define MRPIXEL_TRANSLUCENT

// Requiere common.glsl y depthtex0 declarado.

vec3 playerPosAt(ivec2 q, float d) {
    return viewToPlayer(screenToView((vec2(q) + 0.5) / viewSize(), d));
}

// Normal geométrica desde depthtex0; en cada eje, el vecino de profundidad más parecida
vec3 depthNormal(ivec2 px, float d0, vec3 p0) {
    ivec2 lim = ivec2(viewSize()) - 1;
    ivec2 qr = min(px + ivec2(1, 0), lim);
    ivec2 ql = max(px - ivec2(1, 0), ivec2(0));
    ivec2 qu = min(px + ivec2(0, 1), lim);
    ivec2 qd = max(px - ivec2(0, 1), ivec2(0));
    float dr = texelFetch(depthtex0, qr, 0).r;
    float dl = texelFetch(depthtex0, ql, 0).r;
    float du = texelFetch(depthtex0, qu, 0).r;
    float dd = texelFetch(depthtex0, qd, 0).r;
    vec3 dx = abs(dr - d0) < abs(dl - d0) ? playerPosAt(qr, dr) - p0 : p0 - playerPosAt(ql, dl);
    vec3 dy = abs(du - d0) < abs(dd - d0) ? playerPosAt(qu, du) - p0 : p0 - playerPosAt(qd, dd);
    vec3 n = cross(dx, dy);
    if (dot(n, n) < 1e-14) return vec3(0.0, 1.0, 0.0);
    n = normalize(n);
    return dot(n, p0) > 0.0 ? -n : n;   // mirando hacia la cámara
}

// Superficie translúcida delantera. colortex6 guarda el último translúcido escrito; si no coincide con la
// profundidad, se reconstruye
void frontTranslucent(ivec2 px, vec2 uv, vec4 tdat, float d0, bool laterOpaque,
                      out float surfDepth, out vec3 normal, out int mat, out float skyL) {
    surfDepth = tdat.w;
    normal = decodeNormal(tdat.xy);
    mat = int(floor(tdat.z + 0.001));
    skyL = fract(tdat.z) / 0.99;
    if (!laterOpaque && d0 < tdat.w - 2e-6) {
        surfDepth = d0;
        normal = depthNormal(px, d0, viewToPlayer(screenToView(uv, d0)));
        mat = MAT_GLASS;
    }
}

#endif
