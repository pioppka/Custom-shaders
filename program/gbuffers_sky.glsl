// Sol, luna y estrellas (el degradado va en deferred)

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

out vec2 texcoord;
out vec4 vcolor;
out float tiledSky;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vcolor = gl_Color;
    // cielo del End: UV 0..16
    tiledSky = max(texcoord.x, texcoord.y) > 1.5 ? 1.0 : 0.0;
    gl_Position = ftransform();
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

#include "/lib/sky.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 vcolor;
in float tiledSky;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
#ifdef PROGRAM_SKYBASIC
    if (renderStage != MC_RENDER_STAGE_STARS) discard;
    #ifdef STARS
    outColor = vec4(toLinear(vcolor.rgb) * STAR_BRIGHTNESS, vcolor.a);
    #else
    discard;
    #endif
#else
    vec4 c = texture(gtexture, texcoord) * vcolor;
    // End: fuera la textura de cielo de vanilla (llega sin oscurecer)
    if (isEnd() && tiledSky > 0.0) discard;
    vec3 col = toLinear(c.rgb);
    if (renderStage == MC_RENDER_STAGE_SUN) col *= SUN_BRIGHTNESS_SKY;
    else if (renderStage == MC_RENDER_STAGE_MOON) col *= MOON_BRIGHTNESS_SKY;
    outColor = vec4(col, c.a);
#endif
}

#endif
