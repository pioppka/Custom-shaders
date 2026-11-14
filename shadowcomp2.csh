#version 430

// Olas interactivas: ecuación de ondas a 60 Hz fijos (c² constante); las entidades hunden el agua. Canal b: espuma
// que se reparte a las vecinas y se apaga a distinto ritmo según la zona.

#include "/lib/settings.glsl"

layout(local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(64, 64, 1);   // WATER_SIM_SIZE / 16

#ifdef WATER_SIM

#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/watersim.glsl"

uniform float frameTime;
uniform sampler2D waveSamplerA;
uniform sampler2D waveSamplerB;
uniform usampler2D waveImpulseSampler;

layout(rgba16f) writeonly uniform image2D waveImgA;
layout(rgba16f) writeonly uniform image2D waveImgB;

const float SIM_C2 = 0.42;   // ~0.65 celdas por paso

// en frames pares se lee B y se escribe A; alfa = 1 marca lo escrito
vec2 prevState(ivec2 i) {
    i &= ivec2(SIM_MASK);
    vec4 s = (frameCounter & 1) == 0 ? texelFetch(waveSamplerB, i, 0) : texelFetch(waveSamplerA, i, 0);
    if (s.a != 1.0 || any(isnan(s.rg)) || any(isinf(s.rg))) return vec2(0.0);
    return s.rg;
}

float prevFoam(ivec2 i) {
    i &= ivec2(SIM_MASK);
    vec4 s = (frameCounter & 1) == 0 ? texelFetch(waveSamplerB, i, 0) : texelFetch(waveSamplerA, i, 0);
    return s.a == 1.0 && !isnan(s.b) ? s.b : 0.0;
}

// ruido de valor fijo, ~1 bloque
float foamNoise(ivec2 i) {
    vec2 p = vec2(i) / 12.0;
    vec2 c = floor(p);
    vec2 f = p - c;
    f = f * f * (3.0 - 2.0 * f);
    vec4 h = fract(sin(vec4(dot(c, vec2(127.1, 311.7)), dot(c + vec2(1.0, 0.0), vec2(127.1, 311.7)),
                            dot(c + vec2(0.0, 1.0), vec2(127.1, 311.7)), dot(c + 1.0, vec2(127.1, 311.7)))) * 43758.5453);
    return mix(mix(h.x, h.y, f.x), mix(h.z, h.w, f.x), f.y);
}

float impulseAt(ivec2 i) {
    return texelFetch(waveImpulseSampler, i & ivec2(SIM_MASK), 0).r > 0u ? 1.0 : 0.0;
}

void main() {
    ivec2 i = ivec2(gl_GlobalInvocationID.xy);

    vec2 s = prevState(i);
    float h = s.x;
    float hp = s.y;
    float foam = prevFoam(i);

    bool tick = floor(frameTimeCounter * 60.0) != floor((frameTimeCounter - frameTime) * 60.0)
             || frameTime >= 1.0 / 60.0;
    if (tick) {
        float sum = prevState(i + ivec2(1, 0)).x + prevState(i - ivec2(1, 0)).x
                  + prevState(i + ivec2(0, 1)).x + prevState(i - ivec2(0, 1)).x;
        float hn = (2.0 * h - hp + SIM_C2 * (sum - 4.0 * h)) * RIPPLE_DURATION;

        // las entidades marcan celdas sueltas: se engordan a una cruz
        float occ = max(impulseAt(i), 0.6 * max(max(impulseAt(i + ivec2(1, 0)), impulseAt(i - ivec2(1, 0))),
                                                max(impulseAt(i + ivec2(0, 1)), impulseAt(i - ivec2(0, 1)))));
        hn = mix(hn, -RIPPLE_STRENGTH, 0.4 * occ);

        // espuma: sólo la agitación fuerte
        float agit = (max(hn, 0.0) + 1.5 * abs(hn - h)) * 1.2 * RIPPLE_FOAM;
        float around = 0.25 * (prevFoam(i + ivec2(1, 0)) + prevFoam(i - ivec2(1, 0)) + prevFoam(i + ivec2(0, 1)) + prevFoam(i - ivec2(0, 1)));
        foam = max(mix(foam, around, 0.35) * mix(0.984, 0.995, foamNoise(i)), smoothstep(0.35, 0.90, agit));

        hp = h;
        h = hn;
    }

    // sin agua reciente o salto de cámara: agua quieta
    vec2 surf = waterSurf.cells[simSlot(i)];
    ivec3 jump = abs(cameraPositionInt - previousCameraPositionInt);
    if (simAge(surf.g) > 240.0 || max(jump.x, jump.z) > 8) {
        h = 0.0;
        hp = 0.0;
        foam = 0.0;
    }

    // borde de la ventana toroidal
    ivec2 camIdx = simIndex(simCell(vec3(0.0)));
    ivec2 d = (i - camIdx) & ivec2(SIM_MASK);
    d -= ivec2(greaterThanEqual(d, ivec2(SIM_N / 2))) * SIM_N;
    float edge = 1.0 - smoothstep(float(SIM_N / 2 - 40), float(SIM_N / 2 - 4), float(max(abs(d.x), abs(d.y))));

    vec4 o = vec4(clamp(h * edge, -2.5, 2.5), clamp(hp * edge, -2.5, 2.5), saturate(foam) * edge, 1.0);
    if ((frameCounter & 1) == 0) imageStore(waveImgA, i, o);
    else imageStore(waveImgB, i, o);
}

#else

void main() {}

#endif
