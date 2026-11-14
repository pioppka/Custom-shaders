#version 430

/*
  Al cargar el pack: pone a cero las imágenes de luz del floodfill.
*/

#include "/lib/settings.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 16, 16);

#ifdef FLOODFILL

layout(rgba16f) writeonly uniform image3D lightImgA;
layout(rgba16f) writeonly uniform image3D lightImgB;

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);
    imageStore(lightImgA, v, vec4(0.0));
    imageStore(lightImgB, v, vec4(0.0));
}

#else

void main() {}

#endif
