// Deferred: degradado del cielo

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

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

in vec2 uv;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec4 c = texelFetch(colortex0, px, 0);
    float d = texelFetch(depthtex0, px, 0).r;

    if (d >= SKY_DEPTH) {
        vec3 dir = normalize(mat3(gbufferModelViewInverse) * screenToView(uv, 1.0));
        c.rgb = skyGradient(dir) + c.rgb;
    #ifdef STARS
        if (isEnd()) c.rgb += endStars(dir);
    #endif
        // bajo tierra, más oscuro
        c.rgb = mix(c.rgb, CAVE_SKY, undergroundFactor());
        c.a = 1.0;
    }
    outColor = c;
}

#endif
