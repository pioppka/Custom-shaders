#ifndef MRPIXEL_BUFFERS
#define MRPIXEL_BUFFERS

/*
  colortex0  RGBA16F  color HDR de la escena
  colortex1  RGBA16   normal (octaedro) + material + cobertura
  colortex2  RGBA16F  luz que reciben los bordes (para los bordes iluminados)
  colortex3  RGBA16F  brillo para el glow (con mipmaps)
  colortex4  RGBA8    suavidad, F0/metal, luz de cielo
  colortex5  RGBA16F  capa translúcida (premultiplicada)
  colortex6  RGBA32F  translúcidos: normal, material+cielo, profundidad
  colortex7  RGBA16F  reflejo plástico difuso (experimental)

const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA8;
const int colortex5Format = RGBA16F;
const int colortex6Format = RGBA32F;
const int colortex7Format = RGBA16F;

const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex3Clear = false;
const bool colortex4Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex5Clear = true;
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex6Clear = true;
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const bool colortex7Clear = true;
const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const bool shadowcolor0Clear = true;
const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);
*/

#endif
