// Terreno translúcido: agua, cristal, hielo, slime, portal. Salidas: colortex5 color premultiplicado, colortex6
// normal, material + cielo, profundidad

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

in vec4 mc_Entity;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 vcolor;
out vec3 playerPos;
out vec3 worldNormal;
flat out int blockId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(gl_MultiTexCoord1.xy / 240.0);
    vcolor = gl_Color;
    blockId = int(max(mc_Entity.x, 0.0) + 0.5);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = viewToPlayer(viewPos.xyz);
    vec3 n = gl_NormalMatrix * gl_Normal;
    worldNormal = dot(n, n) > 1e-8 ? mat3(gbufferModelViewInverse) * normalize(n) : vec3(0.0, 1.0, 0.0);

    gl_Position = gl_ProjectionMatrix * viewPos;
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

#define SHADOW_SAMPLING
#ifdef FLOODFILL
    #define VOXEL_READ
#endif
#include "/lib/sky.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"
#include "/lib/pixel.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/rain.glsl"
#ifdef WATER_SIM
    #define WATER_SIM_READ
    #include "/lib/watersim.glsl"
#endif

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 vcolor;
in vec3 playerPos;
in vec3 worldNormal;
flat in int blockId;

/* RENDERTARGETS: 5,6,8 */
layout(location = 0) out vec4 outTrans;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outFogWater;

void main() {
    vec2 texSize = vec2(textureSize(gtexture, 0));
    vec2 uvT = texcoord * texSize * PIXEL_SHADOW_SCALE;
    vec2 dTdx = dFdx(uvT);
    vec2 dTdy = dFdy(uvT);
    vec3 dPdx = dFdx(playerPos);
    vec3 dPdy = dFdy(playerPos);
    vec2 dLdx = dFdx(lmcoord);
    vec2 dLdy = dFdy(lmcoord);
    float dAdx = dFdx(vcolor.a);
    float dAdy = dFdy(vcolor.a);

    vec4 tex = texture(gtexture, texcoord);
    int id = blockId;
    vec3 ng = normalize(worldNormal);
    float depth = gl_FragCoord.z;
    outFogWater = vec4(0.0);

    vec2 st = texelSnapOffset(uvT, dTdx, dTdy);
    vec3 posSnap = playerPos + dPdx * st.x + dPdy * st.y;
    vec2 lm = saturate(lmcoord + dLdx * st.x + dLdy * st.y);
    float ao = saturate(vcolor.a + dAdx * st.x + dAdy * st.y);
#ifndef VANILLA_AO
    ao = 1.0;
#endif

    //------------------------------------------------------------ portal del Nether
    if (id == 14) {
#ifdef PORTAL_EMISSIVE
        // respaldo: normalmente va con lo opaco
        outTrans = vec4(portalEmission(tex.rgb * vcolor.rgb), 1.0);
        outData = vec4(encodeNormal(ng), float(MAT_PORTAL) + lm.y * 0.99, depth);
        return;
#endif
    }

    //------------------------------------------------------------ agua
    if (id == 10) {
        ivec3 wrap = cameraPositionInt & ivec3(1023);
        // rejilla propia del agua (WATER_PIXELS)
        vec3 wpos = playerPos + cameraPositionFract + vec3(wrap);
        bool topFace = ng.y > 0.5;
        float t = frameTimeCounter;

        vec2 cell = (floor(wpos.xz * float(WATER_PIXELS)) + 0.5) / float(WATER_PIXELS);
        vec3 cellPos = topFace ? vec3(cell.x, wpos.y, cell.y) - cameraPositionFract - vec3(wrap) : posSnap;
        // luz y sombra en la más gruesa de las dos rejillas
        bool lightCoarser = (length(dPdx) + length(dPdy)) * float(WATER_PIXELS) > 1.4 * (length(dTdx) + length(dTdy));
        vec3 litPos = lightCoarser ? posSnap : cellPos;
        vec3 Nw = ng;
    #ifdef WATER_WAVES
        // de lejos, plana
        float waveFade = 1.0 - smoothstep(20.0, 56.0, length(cellPos));
        if (topFace && waveFade > 0.0) Nw = normalize(mix(ng, waterWaveNormal(cell, t), waveFade));
    #else
        float waveFade = 0.0;
    #endif
        float rippleRing = 0.0;
    #ifdef RAIN_RIPPLES
        float rainHere = rainStrength * rainExposure(cellPos, lm.y);
        if (topFace && rainHere > 0.01) {
            vec2 rslope;
            rippleRing = rainRipples(cell, t, rainHere * 0.9, rslope);
            Nw = normalize(Nw + vec3(-rslope.x, 0.0, -rslope.y));
        }
    #endif

        // olas interactivas
        float simFoam = 0.0;
    #ifdef WATER_SIM
        ivec2 sc = simCell(cellPos);
        if (topFace && simInWindow(sc)) {
            // superficie del agua para la simulación y el pase de sombras
            float surfY = cellPos.y + cameraPositionFract.y + float(cameraPositionInt.y);
            waterSurf.cells[simSlot(simIndex(sc))] = vec2(surfY, float(frameCounter));
            vec2 s0 = simState(sc);
            float hx = simState(sc + ivec2(1, 0)).x;
            float hz = simState(sc + ivec2(0, 1)).x;
            float simFade = 1.0 - smoothstep(16.0, 40.0, length(cellPos));
            Nw = normalize(Nw + vec3(s0.x - hx, 0.0, s0.x - hz) * 0.7 * simFade);
            // espuma en su rejilla (FOAM_PIXELS)
            float FP = FOAM_PIXELS;
            vec2 fc = (floor(wpos.xz * FP) + 0.5) / FP;
            vec2 g = fc * float(WATER_PIXELS) - 0.5;
            ivec2 off = sc - ivec2(floor(cell * float(WATER_PIXELS)));
            ivec2 b = ivec2(floor(g)) + off;
            vec2 fg = fract(g);
            float f = mix(mix(simFoamAt(b), simFoamAt(b + ivec2(1, 0)), fg.x),
                          mix(simFoamAt(b + ivec2(0, 1)), simFoamAt(b + ivec2(1, 1)), fg.x), fg.y);
            // tres bandas de fuera a dentro: azul del agua más claro, celeste, blanco
            simFoam = f > 0.62 ? 1.0 : (f > 0.38 ? 0.67 : (f > 0.16 ? 0.34 : 0.0));
        }
    #endif

        vec3 V = -normalize(cellPos);
        vec3 L = lightDirWorld();
        vec3 sunCol = celestialLightColor();
        float skyFade = mainLightFade(lm.y);
        vec3 shadow = skyFade > 0.0 ? getShadow(litPos, ng) : vec3(0.0);

        vec3 blDir;
        vec3 bl = getBlockLight(litPos, ng, lm.x, blDir);

        vec3 base = waterBaseColor(tex.rgb, vcolor.rgb);
	outFogWater = vec4(
    		waterBaseColor(vec3(1.0), vcolor.rgb),
    		gl_FragCoord.z
	);

        //vec3 fogWaterColor = waterBaseColor(vec3(1.0), vcolor.rgb);

        vec3 amb = overworldSky() ? ambientSkyLight() * (lm.y * lm.y * 0.85 + lm.y * 0.15) : ambientSkyLight();
        bl = limitBlockLight(bl, sunCol * shadow * skyFade * 0.55 + amb * 1.2, lm.y);
        vec3 diffuse = base * (sunCol * shadow * skyFade * 0.55 * saturate(dot(Nw, L) * 0.5 + 0.5)
                     + amb * 1.2 + bl + vec3(0.06) * MIN_LIGHT);

        // destello del sol por celda
        vec3 R = reflect(-V, Nw);
        float rl = saturate(dot(R, L));
        float g = smoothstep(0.9965, 0.9985, rl);
    #ifdef WATER_SPARKLE
        float sparkle = step(0.93, hash12(cell * 37.0 + floor(t * 3.0))) * smoothstep(0.955, 0.995, rl) * waveFade;
        g = max(g, sparkle);
    #endif
        vec3 glint = celestialGlintColor() * shadow * skyFade * g * 6.0;

        // espuma de las olas
        // paleta y luz de la espuma de la orilla
        vec3 foamLight = sunCol * 0.7 * lm.y + ambientSkyLight() * (0.4 + lm.y) + vec3(0.05);
    #ifdef FLOODFILL
        foamLight += limitBlockLight(bl, foamLight, lm.y);
    #endif
        vec3 foamCol = simFoam > 0.9 ? vec3(0.97, 0.99, 1.00) : (simFoam > 0.5 ? vec3(0.82, 0.94, 1.00) : vec3(0.62, 0.86, 1.00));
        diffuse = mix(diffuse, foamCol * foamLight, simFoam > 0.0 ? mix(0.75, 1.0, simFoam) : 0.0);
        glint *= 1.0 - simFoam;

        float alpha = mix(WATER_ALPHA, 0.95, simFoam);
        vec3 ringCol = vec3(0.30, 0.34, 0.38) * (amb + sunCol * shadow * skyFade * 0.5 + vec3(0.03)) * rippleRing;
        outTrans = vec4(diffuse * alpha + glint + ringCol, alpha);
        outData = vec4(encodeNormal(Nw), float(MAT_WATER) + lm.y * 0.99, depth);
        return;
    }

    // ------------------------------------------------------------ cristal / hielo / slime
    // el cristal transparente refracta también por dentro
    if (tex.a < 0.004 && id != 11) discard;
    vec3 albedo = saturateColor(toLinear(tex.rgb * vcolor.rgb), ALBEDO_SATURATION);
    int mat = MAT_GLASS;
    if (id == 12) mat = MAT_ICE;
    if (id == 13) mat = MAT_SLIME;

    vec3 posLight = posSnap;
    vec3 posShadow = posSnap;

    LitOut lit = shadeToon(albedo, ng, ng, posLight, posShadow, lm, ao, 0.85, 0.0, 0.0, 0.0);
    float alpha = tex.a;
    outTrans = vec4(lit.color * alpha, alpha);
    outData = vec4(encodeNormal(ng), float(mat) + lm.y * 0.99, depth);
}

#endif
