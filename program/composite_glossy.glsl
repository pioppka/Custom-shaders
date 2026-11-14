// Composite 1: reflejo plástico (espejo por píxel en colortex7, lo desenfocan 2/3)

#include "/lib/settings.glsl"
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

#define SHADOW_SAMPLING
#ifdef FLOODFILL
    #define VOXEL_READ
#endif
#include "/lib/sky.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;

#include "/lib/raytrace.glsl"
#include "/lib/reflect.glsl"

in vec2 uv;

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outRefl;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float d0 = texelFetch(depthtex0, px, 0).r;
    outRefl = vec4(0.0);
    if (d0 >= SKY_DEPTH || isEyeInWater == 1) return;

    vec4 gdat = texelFetch(colortex1, px, 0);
    int mat = decodeMaterial(gdat.b);
    if (plasticReflectAmount(mat) <= 0.0) return;

    vec4 tdat = texelFetch(colortex6, px, 0);
    if (tdat.w < 1.0 && tdat.w <= d0 + 1e-6) return;

    vec3 N = decodeNormal(gdat.rg);
    vec3 ppos = viewToPlayer(screenToView(uv, d0));
    float skyL = texelFetch(colortex4, px, 0).b;
    vec3 V = normalize(ppos);

#if REFLECTION_MODE > 0
    outRefl = vec4(reflectionColor(ppos, N, V, skyL, 28, 48, true), 1.0);
#else
    outRefl = vec4(skyReflection(reflect(V, N), skyL, true), 1.0);
#endif
}

#endif
