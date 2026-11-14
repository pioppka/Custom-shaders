#ifndef MRPIXEL_UNIFORMS
#define MRPIXEL_UNIFORMS

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 cameraPositionFract;
uniform ivec3 cameraPositionInt;
uniform ivec3 previousCameraPositionInt;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform float sunAngle;

uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;
uniform float frameTimeCounter;

uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;

uniform float rainStrength;
uniform float wetness;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform bool hasSkylight;
uniform bool hasCeiling;
uniform float ambientLight;        // luz ambiente de la dimensión: Overworld 0, Nether 0.1, End 0.25
uniform float endFlashIntensity;   // destellos del cielo del End (26.x)
uniform int renderStage;

#endif
