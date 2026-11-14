#ifndef MRPIXEL_PIXEL
#define MRPIXEL_PIXEL

// Iluminación por texel: desplazamiento en pantalla (s, t) hasta el centro del texel a partir de las derivadas; los
// atributos lineales se evalúan ahí

// uvTexels: coordenada de textura en texels; dTdx/dTdy: sus derivadas
vec2 texelSnapOffset(vec2 uvTexels, vec2 dTdx, vec2 dTdy) {
    vec2 d = floor(uvTexels) + 0.5 - uvTexels;
    float det = dTdx.x * dTdy.y - dTdx.y * dTdy.x;
    if (abs(det) < 1e-10) return vec2(0.0);

    // sólo si el texel es menor que un píxel en las dos direcciones
    float texelsPerPixel = min(length(dTdx), length(dTdy));
    if (texelsPerPixel > 1.5) return vec2(0.0);

    vec2 st = vec2(d.x * dTdy.y - d.y * dTdy.x, dTdx.x * d.y - dTdx.y * d.x) / det;
    if (any(greaterThan(abs(st), vec2(512.0)))) return vec2(0.0);
    return st;
}

#endif
