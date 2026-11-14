// Composite 2 / 3: desenfoque bilateral del reflejo plástico (horizontal con BLUR_HORIZONTAL)

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D colortex1;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outRefl;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec2 res = viewSize();
    vec4 c0 = texelFetch(colortex7, px, 0);
    float d0 = texelFetch(depthtex0, px, 0).r;
    if (d0 >= SKY_DEPTH || c0.a <= 0.0) {
        outRefl = c0;
        return;
    }

    vec3 p0 = screenToView((vec2(px) + 0.5) / res, d0);
    vec3 n0 = mat3(gbufferModelView) * decodeNormal(texelFetch(colortex1, px, 0).rg);
    float radius = float(PLASTIC_REFL_BLUR) * max(res.y / 1080.0, 1.0);
    float planeTol = 0.04 + 0.01 * -p0.z;

#ifdef BLUR_HORIZONTAL
    const ivec2 dir = ivec2(1, 0);
#else
    const ivec2 dir = ivec2(0, 1);
#endif

    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -8; i <= 8; i++) {
        float x = float(i) / 8.0;
        ivec2 q = clamp(px + dir * int(round(x * radius)), ivec2(0), ivec2(res) - 1);
        vec4 cq = texelFetch(colortex7, q, 0);
        if (cq.a <= 0.0) continue;
        float dq = texelFetch(depthtex0, q, 0).r;
        vec3 pq = screenToView((vec2(q) + 0.5) / res, dq);
        vec3 nq = mat3(gbufferModelView) * decodeNormal(texelFetch(colortex1, q, 0).rg);
        float w = exp(-3.0 * x * x)
                * exp(-abs(dot(pq - p0, n0)) / planeTol)
                * pow(saturate(dot(n0, nq)), 16.0);
        acc += cq * w;
        wsum += w;
    }
    outRefl = wsum > 1e-5 ? acc / wsum : c0;
}

#endif
