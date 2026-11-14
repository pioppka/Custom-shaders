#ifndef MRPIXEL_SKY
#define MRPIXEL_SKY

// Requiere settings, uniforms y common

vec3 sunDirWorld() { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 lightDirWorld() { return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); }

float sunElevation() { return sunDirWorld().y; }

// En el End la hora está fija: el sol es su luz direccional
bool overworldSky() { return hasSkylight && !isEnd(); }

// Luz principal según la luz de cielo del lightmap
float mainLightFade(float skyLm) {
    if (overworldSky()) return smoothstep(0.02, 0.25, skyLm);
    return isEnd() ? 1.0 : 0.0;
}

const vec3 CAVE_SKY = vec3(0.006, 0.010, 0.028);   // azul muy oscuro

// 0 al aire libre, 1 bajo tierra
float undergroundFactor() {
    if (!overworldSky()) return 0.0;
    float noSky = 1.0 - saturate(float(eyeBrightnessSmooth.y) / 160.0);
    float deep = saturate(-cameraPosition.y / 64.0);
    return max(noSky, deep);
}

// Cuánto cielo se refleja
float skyVisibility(float skyLm) {
    return overworldSky() ? smoothstep(0.0, 0.6, skyLm) : 1.0;
}

float dayFactor() { return smoothstep(-0.10, 0.22, sunElevation()); }

float sunsetFactor() {
    float e = sunElevation();
    return smoothstep(-0.22, 0.0, e) * (1.0 - smoothstep(0.04, 0.38, e));
}

// Luz del sol/luna
vec3 celestialLightColor() {
    // End y Nether: sin sol
    if (!overworldSky()) return vec3(0.0);
    float e = sunElevation();
    vec3 c;
    if (sunAngle < 0.5) {
        vec3 noon = vec3(1.00, 0.93, 0.82);
        vec3 low = vec3(1.00, 0.52, 0.24);
        c = mix(low, noon, smoothstep(0.02, 0.40, e)) * 1.15 * SUN_BRIGHTNESS;
        c *= smoothstep(0.0, 0.07, e);
    } else {
        c = vec3(0.30, 0.40, 0.78) * 0.16 * NIGHT_BRIGHTNESS;
        c *= smoothstep(0.0, 0.07, -e);
    }
    return c * (1.0 - 0.80 * rainStrength);
}

// Color de los bordes con sol/luna, sin la intensidad
vec3 celestialEdgeColor() {
    if (!overworldSky()) return vec3(0.0);
    float e = sunElevation();
    vec3 c;
    if (sunAngle < 0.5) {
        vec3 noon = vec3(1.00, 0.88, 0.60);
        vec3 low = vec3(1.00, 0.46, 0.14);
        c = mix(low, noon, smoothstep(0.03, 0.45, e)) * smoothstep(0.0, 0.07, e);
    } else {
        c = vec3(0.35, 0.55, 1.00) * 0.60 * NIGHT_BRIGHTNESS * smoothstep(0.0, 0.07, -e);
    }
    return c * (1.0 - 0.75 * rainStrength);
}

// Brillo del disco del sol/luna para destellos y reflejos; la luna según MOON_BRIGHTNESS_SKY y la fase
vec3 celestialGlintColor() {
    if (!overworldSky() || sunAngle < 0.5) return celestialLightColor();
    float lit = mix(0.12, 1.0, abs(float(moonPhase) - 4.0) / 4.0);
    return vec3(0.45, 0.58, 1.00) * (MOON_BRIGHTNESS_SKY * 0.26) * lit
         * smoothstep(0.0, 0.07, -sunElevation()) * (1.0 - 0.80 * rainStrength);
}

// Luz ambiente
vec3 ambientSkyLight() {
    if (!overworldSky()) {
        if (hasCeiling) {
            // Nether: con el color de niebla del bioma
            vec3 fogT = toLinear(fogColor);
            vec3 tint = fogT / max(max3(fogT), 1e-4);
            return mix(vec3(0.30, 0.17, 0.12), tint * 0.26, 0.40) * AMBIENT_BRIGHTNESS;
        }
        return vec3(0.055, 0.020, 0.130) * (1.0 + endFlashIntensity) * AMBIENT_BRIGHTNESS;
    }
    float day = dayFactor();
    float sunset = sunsetFactor();
    vec3 dayAmb = vec3(0.40, 0.50, 0.70);
    vec3 sunsetAmb = vec3(0.45, 0.34, 0.40);
    vec3 nightAmb = vec3(0.030, 0.040, 0.085) * NIGHT_BRIGHTNESS;
    vec3 c = mix(nightAmb, dayAmb, day);
    c = mix(c, sunsetAmb, sunset * 0.6);
    c = mix(c, vec3(luminance(c)) * vec3(0.85, 0.90, 1.00) * 0.75, rainStrength);
    return c * AMBIENT_BRIGHTNESS;
}

// De día, a cielo abierto, la luz de bloque no pasa del pleno sol
float blockLightDayWeight(float skyLm) {
    if (!overworldSky()) return 0.0;
    return dayFactor() * smoothstep(0.30, 0.90, skyLm);
}

// envLight: sol y cielo que ya recibe la superficie
vec3 limitBlockLight(vec3 bl, vec3 envLight, float skyLm) {
    float day = blockLightDayWeight(skyLm);
    if (day <= 0.0) return bl;
    float full = luminance(celestialLightColor()) + luminance(ambientSkyLight());
    float room = max(full - luminance(envLight), 0.0);
    float lb = luminance(bl);
    float keep = lb > 1e-5 ? min(1.0, room / lb) : 1.0;
    return bl * mix(1.0, keep, day);
}

vec3 dimensionFogColor() {
    if (hasCeiling) {
        vec3 f = toLinear(fogColor);
        return saturateColor(f, 1.25) * 1.2 + vec3(0.02, 0.005, 0.0);
    }
    return vec3(0.060, 0.012, 0.120);
}

// Cielo del atardecer: dorado en el horizonte a malva arriba; del otro lado, melocotón. Paradas por altura (grados),
// mezcla en sRGB. side: 1 del lado del sol
vec3 sunsetSky(float a, float side) {
    const float A[6] = float[6](-35.0, 0.0, 20.0, 35.0, 55.0, 90.0);
    const vec3 SUN[6] = vec3[6](vec3(2.081, 0.819, 0.274), vec3(1.745, 0.616, 0.162), vec3(0.886, 0.321, 0.117),
                                vec3(0.541, 0.214, 0.115), vec3(0.136, 0.067, 0.087), vec3(0.033, 0.019, 0.062));
    const vec3 AWAY[6] = vec3[6](vec3(1.229, 0.631, 0.452), vec3(0.862, 0.407, 0.301), vec3(0.475, 0.233, 0.212),
                                 vec3(0.279, 0.150, 0.172), vec3(0.104, 0.062, 0.104), vec3(0.033, 0.019, 0.062));
    float x = clamp(a, -35.0, 90.0);
    int i = x < 0.0 ? 0 : (x < 20.0 ? 1 : (x < 35.0 ? 2 : (x < 55.0 ? 3 : 4)));
    float t = (x - A[i]) / (A[i + 1] - A[i]);
    vec3 toward = mix(toSRGB(SUN[i]), toSRGB(SUN[i + 1]), t);
    vec3 away = mix(toSRGB(AWAY[i]), toSRGB(AWAY[i + 1]), t);
    return toLinear(mix(away, toward, side));
}

vec3 skyGradient(vec3 dir) {
    if (!overworldSky()) {
        if (hasCeiling) return dimensionFogColor();
        // End: negro en el horizonte a violeta arriba
        float h = saturate(asin(clamp(dir.y, -1.0, 1.0)) / (PI * 0.5));
        vec3 c = vec3(0.110, 0.018, 0.240) * pow(h, 2.2);
        float g = saturate(dot(dir, lightDirWorld()));
        c += vec3(0.30, 0.10, 0.60) * endFlashIntensity * (0.30 + 0.70 * g);
        return c;
    }

    float day = dayFactor();
    float sunset = sunsetFactor();
    vec3 sunDir = sunDirWorld();

    // día: azul oscuro arriba, turquesa en medio, azul cielo en el horizonte
    const vec3 dayZenith = vec3(0.0087, 0.0320, 0.220);
    const vec3 dayMid = vec3(0.030, 0.430, 1.230);
    const vec3 dayHorizon = vec3(0.460, 0.830, 1.380);
    const vec3 nightZenith = vec3(0.0008, 0.0012, 0.0070);
    const vec3 nightHorizon = vec3(0.0060, 0.0100, 0.0400);

    vec3 zenith = mix(nightZenith, dayZenith, day);
    vec3 horizon = mix(nightHorizon, dayHorizon, day);
    vec3 mid = mix(mix(nightHorizon, nightZenith, 0.5), dayMid, day);

    // Degradado por ángulo de altura, mezclado en sRGB
    float a = asin(clamp(dir.y, -1.0, 1.0)) * (180.0 / PI);
    vec3 c = a < 15.0 ? toLinear(mix(toSRGB(horizon), toSRGB(mid), saturate((a + 35.0) / 50.0)))
                      : toLinear(mix(toSRGB(mid), toSRGB(zenith), saturate((a - 15.0) / 75.0)));

    if (sunset > 0.001) {
        vec2 h = dir.xz;
        vec2 s = sunDir.xz;
        float towardSun = (length(h) > 1e-4 && length(s) > 1e-4) ? dot(normalize(h), normalize(s)) * 0.5 + 0.5 : 0.5;
        c = mix(c, sunsetSky(a, towardSun * towardSun), sunset);
    }

    // halo del sol
    float sd = saturate(dot(dir, sunDir));
    c += vec3(1.0, 0.75, 0.45) * pow(sd, 24.0) * 0.35 * (day * 0.6 + sunset);

    c = mix(c, vec3(luminance(c)) * vec3(0.85, 0.92, 1.0) * 0.65, rainStrength * 0.85);
    return c;
}

// Color de niebla en una dirección
vec3 fogColorDir(vec3 dir) {
    if (!overworldSky()) return hasCeiling ? dimensionFogColor() : skyGradient(dir);
    vec3 c = skyGradient(normalize(vec3(dir.x, max(dir.y, 0.0), dir.z)));
    return mix(c, CAVE_SKY, undergroundFactor());
}

#ifdef STARS
// Estrellas del End: cuadrícula sobre las caras de un cubo
vec3 endStars(vec3 dir) {
    vec3 a = abs(dir);
    vec2 p;
    float face;
    if (a.y > max(a.x, a.z)) { p = dir.xz / a.y; face = dir.y > 0.0 ? 0.0 : 1.0; }
    else if (a.x > a.z)      { p = dir.yz / a.x; face = dir.x > 0.0 ? 2.0 : 3.0; }
    else                     { p = dir.xy / a.z; face = dir.z > 0.0 ? 4.0 : 5.0; }
    vec2 cell = floor(p * 90.0);
    float h = hash12(cell + face * 211.0);
    if (h < 0.993) return vec3(0.0);
    float twinkle = 0.6 + 0.4 * sin(frameTimeCounter * (1.5 + h * 3.0) + h * 40.0);
    return mix(vec3(0.75, 0.55, 1.00), vec3(1.0), fract(h * 97.0)) * twinkle * STAR_BRIGHTNESS * 0.08;
}
#endif

#endif
