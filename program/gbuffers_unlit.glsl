// Programas sin luz: basic, line, textured, beaconbeam, spidereyes, armor_glint, damagedblock, lightning.
// gbuffers_line se compila en modo core: las líneas se ensanchan aquí como en rendertype_lines.vsh.

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

out vec2 texcoord;
out vec4 vcolor;

#ifdef PROGRAM_LINE
in vec3 vaPosition;
in vec3 vaNormal;
in vec4 vaColor;
in float LineWidth;   // píxeles

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

vec4 lineClip(vec3 p) {
    vec4 v = modelViewMatrix * vec4(p, 1.0);
    v.xyz *= 1.0 - 1.0 / 256.0;
    return projectionMatrix * v;
}

// 4 vértices por segmento: pares a un lado, impares al otro
void main() {
    vec2 res = vec2(viewWidth, viewHeight);
    vec4 a = lineClip(vaPosition);
    vec4 b = lineClip(vaPosition + vaNormal);
    float side = 1.0;
    // el otro extremo detrás de la cámara
    if (b.w < 1e-3) {
        b = lineClip(vaPosition - vaNormal);
        side = -1.0;
    }
    vec2 dir = (b.xy / max(b.w, 1e-3) - a.xy / a.w) * res * side;
    dir = dot(dir, dir) > 1e-12 ? normalize(dir) : vec2(1.0, 0.0);
    float width = LineWidth > 0.0 ? LineWidth : 2.5;
    vec2 offset = vec2(-dir.y, dir.x) * width / res;
    if (offset.x < 0.0) offset = -offset;
    if (gl_VertexID % 2 != 0) offset = -offset;

    gl_Position = a + vec4(offset * a.w, 0.0, 0.0);
    texcoord = vec2(0.5);
    vcolor = vaColor;
}
#else
void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vcolor = gl_Color;
    gl_Position = ftransform();
}
#endif

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 vcolor;

#ifdef PROGRAM_LINE
/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;
#else
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;
#endif

void main() {
#if defined PROGRAM_BASIC || defined PROGRAM_LINE || defined PROGRAM_LIGHTNING
    vec4 c = vcolor;
#else
    vec4 c = texture(gtexture, texcoord) * vcolor;
#endif
    if (c.a < 0.004) discard;

#if defined PROGRAM_DAMAGE
    outColor = c;                                                // mezcla multiplicativa vanilla
#elif defined PROGRAM_BEACON
    outColor = vec4(toLinear(c.rgb) * 3.0, c.a);
#elif defined PROGRAM_EYES
    outColor = vec4(toLinear(c.rgb) * EMISSIVE_BRIGHTNESS, c.a);
#elif defined PROGRAM_LIGHTNING
    outColor = vec4(toLinear(c.rgb) * 4.0, c.a);
#elif defined PROGRAM_GLINT
    outColor = vec4(toLinear(c.rgb) * 1.2, c.a);
#elif defined PROGRAM_LINE
    outColor = vec4(toLinear(c.rgb), c.a);
    // Líneas opacas: material de texto. Las translúcidas no escriben material.
    outData = vec4(encodeNormal(vec3(0.0, 1.0, 0.0)), encodeMaterial(MAT_TEXT), c.a > 0.99 ? 1.0 : 0.0);
#else
    outColor = vec4(toLinear(c.rgb), c.a);
#endif
}

#endif
