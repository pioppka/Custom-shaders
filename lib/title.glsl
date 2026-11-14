#ifndef MRPIXEL_TITLE
#define MRPIXEL_TITLE

// Nombre del pack unos segundos al cargar el shader (frameTimeCounter y frameCounter empiezan en 0)

const int TITLE_FONT[98] = int[98](
    17, 27, 21, 21, 17, 17, 17,   // M
    0, 0, 22, 25, 16, 16, 16,     // r
    30, 17, 17, 30, 16, 16, 16,   // P
    4, 0, 12, 4, 4, 4, 14,        // i
    0, 0, 17, 10, 4, 10, 17,      // x
    0, 0, 14, 17, 31, 16, 14,     // e
    12, 4, 4, 4, 4, 4, 14,        // l
    15, 16, 16, 14, 1, 1, 30,     // S
    16, 16, 22, 25, 17, 17, 17,   // h
    0, 0, 14, 1, 15, 17, 15,      // a
    1, 1, 13, 19, 17, 17, 15,     // d
    0, 0, 15, 16, 14, 1, 30,      // s
    30, 17, 17, 30, 20, 18, 17,   // R
    31, 4, 4, 4, 4, 4, 4          // T
);
const int TITLE_TEXT[15] = int[15](0, 1, 2, 3, 4, 5, 6, -1, 7, 8, 9, 10, 5, 1, 11);   // -1 = espacio
const int TITLE_ACCENT_FROM = 8;   // desde aquí, en color
const int TITLE_WIDTH = 86;
const int TITLE_BAR = 41;   // la barra de acento va bajo "MrPixel"
const vec3 TITLE_ACCENT = vec3(0.33, 0.85, 0.93);

// Píxel de la fuente f: 1 si está encendido
float titleMask(ivec2 f, out bool accent) {
    accent = false;
    if (f.y < 0 || f.y > 6 || f.x < 0) return 0.0;
    int x = f.x;
    for (int i = 0; i < TITLE_TEXT.length(); i++) {
        int g = TITLE_TEXT[i];
        int w = g < 0 ? 3 : 6;
        if (x < w) {
            if (g < 0 || x > 4) return 0.0;
            accent = i >= TITLE_ACCENT_FROM;
            return float((TITLE_FONT[g * 7 + f.y] >> (4 - x)) & 1);
        }
        x -= w;
    }
    return 0.0;
}

// Sobre el color final (sRGB): texto con sombra y barra de acento
vec3 drawTitle(vec3 s, vec2 fragCoord) {
#ifdef LOADING_TITLE
    float t = frameTimeCounter;
    if (t > 6.5 || frameCounter > 30000) return s;
    float a = smoothstep(0.3, 1.1, t) * (1.0 - smoothstep(4.6, 6.2, t));
    if (a <= 0.0) return s;
    float scale = max(1.0, floor(viewHeight / 240.0 + 0.5));
    float rise = 3.0 * (1.0 - smoothstep(0.3, 1.3, t));
    // filas 0-6 texto, 9 barra; desde el 8 % de arriba y el 5 % de la izquierda
    vec2 corner = vec2(floor(viewWidth * 0.05), viewHeight - floor(viewHeight * 0.08) - 10.0 * scale);
    vec2 p = (fragCoord - corner) / scale;
    int fx = int(floor(p.x));
    int row = 9 - int(floor(p.y - rise));
    if (fx < -1 || fx > TITLE_WIDTH + 1 || row < -1 || row > 10) return s;

    bool acc;
    bool accShadow;
    float text = titleMask(ivec2(fx, row), acc);
    float shadow = titleMask(ivec2(fx - 1, row - 1), accShadow);
    float barLen = float(TITLE_BAR) * smoothstep(0.5, 1.6, t);
    float bar = row == 9 && fx >= 0 && float(fx) < barLen ? 1.0 : 0.0;
    float barShadow = row == 10 && fx >= 1 && float(fx - 1) < barLen ? 1.0 : 0.0;

    s = mix(s, vec3(0.0), max(shadow, barShadow) * a * 0.45);
    s = mix(s, acc ? TITLE_ACCENT : vec3(0.97), text * a);
    s = mix(s, TITLE_ACCENT, bar * a * 0.9);
#endif
    return s;
}

#endif
