#ifndef MRPIXEL_WATERSIM
#define MRPIXEL_WATERSIM

// Olas interactivas: alturas en WATER_SIM_SIZE^2 celdas (WATER_PIXELS por bloque), direccionamiento toroidal (c &
// (N-1)). waveImgA/B: altura, altura anterior, ocupación. waveImpulseImg: entidades en el agua. waterSurf
// (bufferObject.1): altura de la superficie y frame en que se vio

const int SIM_N = WATER_SIM_SIZE;
const int SIM_MASK = WATER_SIM_SIZE - 1;
const int SIM_REACH = WATER_SIM_SIZE / 2 - 4;   // celdas útiles desde la cámara

// celda de mundo de una posición del espacio jugador
ivec2 simCell(vec3 playerPos) {
    return ivec2(floor((playerPos.xz + cameraPositionFract.xz) * float(WATER_PIXELS))) + cameraPositionInt.xz * WATER_PIXELS;
}

ivec2 simIndex(ivec2 cell) { return cell & ivec2(SIM_MASK); }

// (altura de la superficie, frame) por celda
layout(std430, binding = 1) buffer MrPixelWaterSurf {
    vec2 cells[];
} waterSurf;

int simSlot(ivec2 i) { return i.y * SIM_N + i.x; }   // i = simIndex(celda)

bool simInWindow(ivec2 cell) {
    ivec2 d = abs(cell - simCell(vec3(0.0)));
    return max(d.x, d.y) < SIM_REACH;
}

// frames desde que se vio agua (frameCounter vuelve a 0 en 720720)
float simAge(float seenFrame) {
    float age = float(frameCounter) - seenFrame;
    return age < 0.0 ? age + 720720.0 : age;
}

#ifdef WATER_SIM_READ
uniform sampler2D waveSamplerA;
uniform sampler2D waveSamplerB;

// (altura, altura anterior); shadowcomp2 escribe A en frames pares y B en impares
vec2 simState(ivec2 cell) {
    ivec2 i = simIndex(cell);
    vec4 s = (frameCounter & 1) == 0 ? texelFetch(waveSamplerA, i, 0) : texelFetch(waveSamplerB, i, 0);
    return s.a == 1.0 ? s.rg : vec2(0.0);
}

// espuma de la celda (0..1)
float simFoamAt(ivec2 cell) {
    ivec2 i = simIndex(cell);
    vec4 s = (frameCounter & 1) == 0 ? texelFetch(waveSamplerA, i, 0) : texelFetch(waveSamplerB, i, 0);
    return s.a == 1.0 ? s.b : 0.0;
}
#endif

#endif
