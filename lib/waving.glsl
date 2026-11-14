#ifndef MRPIXEL_WAVING
#define MRPIXEL_WAVING

// Movimiento de plantas y hojas. uv / midUV: UV del vértice y centro del sprite
vec3 wavingOffset(vec3 playerPos, int id, vec2 uv, vec2 midUV) {
    if (id < 1 || id > 9 || id == 7) return vec3(0.0);

    // posición de mundo envuelta
    vec3 wp = playerPos + cameraPositionFract + vec3(cameraPositionInt & ivec3(1023));
    float t = frameTimeCounter * WAVING_SPEED;

    float wx = sin(t * 1.70 + wp.x * 0.60 + wp.z * 0.40) * 0.6 + sin(t * 2.90 + wp.x * 1.30 - wp.z * 0.90) * 0.4;
    float wz = cos(t * 2.10 + wp.z * 0.70 + wp.x * 0.30) * 0.6 + cos(t * 3.30 - wp.z * 1.10 + wp.x * 0.70) * 0.4;
    vec3 wind = vec3(wx, 0.0, wz);

    bool top = uv.y < midUV.y;
    float amp = 0.0;
    vec3 off = vec3(0.0);

#ifdef WAVING_PLANTS
    if (id == 1 || id == 8 || id == 9) amp = top ? 0.09 : 0.0;
    else if (id == 2) amp = top ? 0.05 : 0.0;
    else if (id == 3) amp = top ? 0.12 : 0.05;
    else if (id == 5) amp = 0.05;
    else if (id == 6) off.y = sin(t * 1.3 + wp.x * 0.8 + wp.z * 0.6) * 0.015;
#endif
#ifdef WAVING_LEAVES
    if (id == 4) {
        amp = 0.035;
        off.y = sin(t * 2.3 + wp.x * 1.7 + wp.y * 1.3 + wp.z * 1.1) * 0.02;
    }
#endif

    amp *= 1.0 + rainStrength * 0.8;
    return off + wind * amp;
}

#endif
