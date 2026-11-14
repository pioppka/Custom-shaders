// Nubes opacas

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

//==============================================================================
#ifdef VERTEX_SHADER

out vec4 vcolor;
out vec3 worldNormal;
out vec3 playerPos;

void main() {
    vcolor = gl_Color;
    playerPos = viewToPlayer((gl_ModelViewMatrix * gl_Vertex).xyz);
    vec3 n = gl_NormalMatrix * gl_Normal;
    worldNormal = dot(n, n) > 1e-8 ? mat3(gbufferModelViewInverse) * normalize(n) : vec3(0.0, 1.0, 0.0);
    gl_Position = ftransform();
}

#endif
//==============================================================================
#ifdef FRAGMENT_SHADER

#include "/lib/sky.glsl"

in vec4 vcolor;
in vec3 worldNormal;
in vec3 playerPos;

/* RENDERTARGETS: 0,1,2,4 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outEdge;
layout(location = 3) out vec4 outPbr;

void main() {
    vec3 n = normalize(worldNormal);
    vec3 L = lightDirWorld();
    vec3 sunCol = celestialLightColor();
    float lit = smoothstep(-0.05, 0.05, dot(n, L));
    float bottom = smoothstep(0.4, 0.9, -n.y);

    // Luz propia: azul claro por debajo, casi blancas al sol; siguen a la luz ambiente y a la del sol
    vec3 ambN = ambientSkyLight() / max(AMBIENT_BRIGHTNESS, 0.01);
    vec3 sunN = sunCol / max(SUN_BRIGHTNESS, 0.01);
    vec3 col = ambN * vec3(1.74, 1.94, 2.22) + sunN * (lit * 1.35);
    col = mix(col, col * vec3(0.90, 0.95, 1.0), bottom * 0.3);
    // tinte del cielo, más fuerte abajo y a lo lejos
    vec3 V = normalize(playerPos);
    float sunset = sunsetFactor();
    col = mix(col, skyGradient(V), 0.15 + 0.15 * bottom + 0.20 * sunset);
    // atardecer: color del horizonte bajo el sol, más hacia él
    vec3 S = sunDirWorld();
    vec3 glow = skyGradient(normalize(vec3(S.x, 0.06, S.z))) * 1.15;
    float toSun = pow(saturate(dot(V, S) * 0.5 + 0.5), 2.0);
    col = mix(col, glow, sunset * (0.35 + 0.45 * toSun));

#ifdef CARTOON_CLOUDS
    float alpha = 1.0;
#else
    float alpha = vcolor.a;
#endif

    float horizonFade = smoothstep(0.02, 0.52, V.y);
    alpha *= horizonFade;

    if (alpha < 0.004) discard;

    //outColor = vec4(vec3(horizonFade), 1.0);
    //outData = vec4(0.0);
    //outEdge = vec4(0.0);
    //outPbr = vec4(0.0);

    outColor = vec4(col, alpha);
    outData = vec4(encodeNormal(n), encodeMaterial(MAT_CLOUD), 1.0);
    outEdge = vec4(celestialEdgeColor() * lit * 0.6, alpha);
    outPbr = vec4(0.0, 0.0, 1.0, 1.0);
}

#endif
