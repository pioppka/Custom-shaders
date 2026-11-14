#version 430

// Copia a extraTexImg (64x64 cada una) amatista, antorchas y arbusto de luciérnagas (cuadro actual). En composite: en
// el pase de sombras Iris no puede cargar texturas nuevas.

#include "/lib/settings.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(80, 8, 1);

#ifdef FLOODFILL

uniform float frameTimeCounter;
uniform sampler2D amethystClusterTex;
uniform sampler2D amethystLargeTex;
uniform sampler2D amethystMediumTex;
uniform sampler2D amethystSmallTex;
uniform sampler2D torchTex;
uniform sampler2D soulTorchTex;
uniform sampler2D redstoneTorchTex;
uniform sampler2D copperTorchTex;
uniform sampler2D fireflyBushTex;
uniform sampler2D fireflyBushGlowTex;   // cuadros en vertical, 3 ticks cada uno

layout(rgba8) writeonly uniform image2D extraTexImg;

// Texel d del cuadro frame de la tira t
vec4 frameTexel(sampler2D t, ivec2 d, int frame) {
    int s = textureSize(t, 0).x;
    return texelFetch(t, d * s / 64 + ivec2(0, frame * s), 0);
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 d = ivec2(p.x & 63, p.y);
    vec4 c;
    switch (p.x >> 6) {
        case 0: c = frameTexel(amethystClusterTex, d, 0); break;
        case 1: c = frameTexel(amethystLargeTex, d, 0); break;
        case 2: c = frameTexel(amethystMediumTex, d, 0); break;
        case 3: c = frameTexel(amethystSmallTex, d, 0); break;
        case 4: c = frameTexel(torchTex, d, 0); break;
        case 5: c = frameTexel(soulTorchTex, d, 0); break;
        case 6: c = frameTexel(redstoneTorchTex, d, 0); break;
        case 7: c = frameTexel(copperTorchTex, d, 0); break;
        case 8: c = frameTexel(fireflyBushTex, d, 0); break;
        default: {
            ivec2 gs = textureSize(fireflyBushGlowTex, 0);
            c = frameTexel(fireflyBushGlowTex, d, int(frameTimeCounter / 0.15) % max(gs.y / max(gs.x, 1), 1));
        }
    }
    imageStore(extraTexImg, p, c);
}

#else
void main() {}
#endif
