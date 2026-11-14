#ifndef MRPIXEL_STATE
#define MRPIXEL_STATE

// Estado entre pases y frames (bufferObject.0, a cero al crearse)
//  impactSeen    partículas de explosión de este frame: 0 píxeles blancos, 1-3 suma de posiciones x4,
//                4 la más cercana (10000 - distancia x100), 5 casi blancos
//  impactState   frame de impacto, dos juegos de 8 (frames pares / impares)
//  fogFade       transición de la niebla de suelo (pares / impares)
//  shadowAnchor  ancla de la rejilla de sombras: entero + fracción; [3] = 1 si ya está puesta
layout(std430, binding = 0) buffer MrPixelState {
    int impactSeen[8];
    float impactState[16];
    float fogFade[2];
    int shadowAnchorInt[4];
    float shadowAnchorFract[4];
} mrState;

#endif
