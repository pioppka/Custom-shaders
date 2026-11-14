// Composite 5: zonas brillantes para el glow (colortex3)

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

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outBloom;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 c = texelFetch(colortex0, px, 0).rgb;
    int mat = decodeMaterial(texelFetch(colortex1, px, 0).b);
    if (mat == MAT_TEXT) c = vec3(0.0);

    // umbral suave sobre el máximo de luminancia y canal
    float l = max(luminance(c), max3(c) * 0.75);
    // con lluvia, más bajo
    float t = BLOOM_THRESHOLD * mix(1.0, 0.4, saturate(rainCameraFog()));
    // el cielo y las nubes no brillan; sol, luna y estrellas sí
    if (mat == MAT_CLOUD) t = max(t, 3.0);
    else if (texelFetch(depthtex0, px, 0).r >= SKY_DEPTH) t = max(t, 1.2);
    float k = t * 0.5;
    float s = clamp(l - t + k, 0.0, 2.0 * k);
    s = s * s / (4.0 * k + 1e-5);
    float contrib = max(s, l - t) / max(l, 1e-5);

    outBloom = vec4(min(c * contrib, vec3(64.0)), 1.0);
}

#endif
