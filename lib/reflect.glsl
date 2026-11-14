#ifndef MRPIXEL_REFLECT
#define MRPIXEL_REFLECT

// Requiere: sky, shadows (SHADOW_SAMPLING), voxel (VOXEL_READ si FLOODFILL), lighting, raytrace.

float fresnelSchlick(float cosT, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - saturate(cosT), 5.0);
}

// Cielo reflejado. withSun: con el disco del sol/luna
vec3 skyReflection(vec3 R, float skyL, bool withSun) {
    vec3 s = skyGradient(R);
    if (withSun) {
        float sd = saturate(dot(R, lightDirWorld()));
        s += celestialGlintColor() * smoothstep(0.9985, 0.9995, sd) * 6.0;
    }
    return s * skyVisibility(skyL) + vec3(0.01, 0.012, 0.02);
}

#if REFLECTION_MODE == 2 && defined FLOODFILL
// Color del punto que tocó el rayo; glow: la parte emisiva
vec3 shadeVoxelHit(vec3 albedo, vec3 hp, vec3 n, float em, float skyL, out vec3 glow) {
    vec3 L = lightDirWorld();
    vec3 sh = getShadow(hp + n * 0.06, n);
    vec3 sunL = celestialLightColor() * softDiffuse(dot(n, L)) * sh * mainLightFade(skyL);
    vec3 ff;
    vec3 ffd;
    float w = sampleFloodfill(hp, n, ff, ffd);
    vec3 bl = ff * FLOODFILL_BRIGHTNESS * 1.3 * w;
    vec3 amb = ambientSkyLight() * (0.25 + 0.75 * skyL);
    bl = limitBlockLight(bl, sunL + amb, skyL);
    glow = albedo * em * EMISSIVE_BRIGHTNESS;
#ifdef WHITE_WORLD
    albedo = WHITE_ALBEDO;
#endif
    return albedo * (sunL + amb + bl + vec3(0.03));
}
#endif

#ifdef SKY_REFLECTIONS
// Cielo reflejado tal como se ve en pantalla en R, promediado en la huella de una celda. w: confianza
vec3 screenSky(vec3 R, vec3 origin, bool withSun, out float w) {
    w = 0.0;
    vec3 rv = mat3(gbufferModelView) * R;
    if (rv.z > -1e-3) return vec3(0.0);
    vec2 res = viewSize();
    vec2 suv = viewToScreen(rv).xy;
    vec2 e = abs(suv * 2.0 - 1.0);
    float edge = 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y));
    if (edge <= 0.0) return vec3(0.0);
#if REFLECTION_PIXELS > 0
    float cellPx = gbufferProjection[1][1] * viewHeight / (2.0 * float(REFLECTION_PIXELS) * max(length(origin), 0.5));
    int k = int(clamp(cellPx + 0.5, 1.0, 4.0));
#else
    int k = 1;
#endif
    bool nearDisc = !withSun && abs(dot(R, sunDirWorld())) > 0.95;
    vec3 grad = skyGradient(R);
    ivec2 q0 = ivec2(suv * res) - k / 2;
    vec3 sum = vec3(0.0);
    float n = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            if (x >= k || y >= k) continue;
            ivec2 q = clamp(q0 + ivec2(x, y), ivec2(0), ivec2(res) - 1);
            bool cloud = decodeMaterial(texelFetch(colortex1, q, 0).b) == MAT_CLOUD;
            if (!cloud && texelFetch(depthtex0, q, 0).r < SKY_DEPTH) continue;
            sum += cloud || !nearDisc ? texelFetch(colortex0, q, 0).rgb : grad;
            n += 1.0;
        }
    }
    if (n < 0.5) return vec3(0.0);
    w = edge * n / float(k * k);
    return sum / n;
}
#endif

// Color reflejado con el modo activo. glow aparte para que llegue al bloom.
vec3 reflectionColorGlow(vec3 origin, vec3 N, vec3 V, float skyL, int ssrSteps, int rtSteps, bool withSun, out vec3 glow) {
    glow = vec3(0.0);
    vec3 R = reflect(V, N);
    vec3 result = vec3(0.0);
    float conf = 0.0;
#if REFLECTION_MODE == 1
    vec3 hc;
    conf = traceScreen(origin + N * 0.03, R, ssrSteps, hc);
    result = hc * conf;
#endif
    float remaining = 1.0 - conf;
    if (remaining > 0.001) {
        vec3 fallback = skyReflection(R, skyL, withSun);
#ifdef SKY_REFLECTIONS
        float sw;
        vec3 ss = screenSky(R, origin, withSun, sw);
        fallback = mix(fallback, ss * skyVisibility(skyL) + vec3(0.01, 0.012, 0.02), sw);
#endif
#if REFLECTION_MODE == 2 && defined FLOODFILL
        vec3 alb;
        vec3 hp;
        vec3 hn;
        float em;
        if (traceVoxels(origin + N * 0.03, R, rtSteps, alb, hp, hn, em)) {
            fallback = shadeVoxelHit(alb, hp, hn, em, skyL, glow);
            glow *= remaining;
        }
#endif
        result += fallback * remaining;
    }
    return result;
}

// Reflejo con la emisión incluida
vec3 reflectionColor(vec3 origin, vec3 N, vec3 V, float skyL, int ssrSteps, int rtSteps, bool withSun) {
    vec3 glow;
    vec3 c = reflectionColorGlow(origin, N, V, skyL, ssrSteps, rtSteps, withSun, glow);
    return c + glow;
}

// Origen del reflejo en la rejilla de REFLECTION_PIXELS
vec3 snapToSurfaceGrid(vec3 p, vec3 N) {
#if REFLECTION_PIXELS > 0
    vec3 an = abs(N);
    if (max3(an) > 0.9) {
        int axis = (an.x > an.y && an.x > an.z) ? 0 : (an.y > an.z ? 1 : 2);
        vec3 wp = p + cameraPositionFract;
        vec3 s = (floor(wp * float(REFLECTION_PIXELS)) + 0.5) / float(REFLECTION_PIXELS);
        s[axis] = wp[axis];
        return s - cameraPositionFract;
    }
#endif
    return p;
}

#endif
