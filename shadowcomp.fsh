#version 430 compatibility

/*
  Pase vacío a propósito: Iris pone una barrera de memoria al activar un programa de fragmento, pero no antes de
  un compute. Sin ella los compute de shadowcomp leen los vóxeles mientras el pase de sombras aún los escribe.
*/

/* RENDERTARGETS: 1 */
layout(location = 0) out vec4 outDummy;

void main() {
    discard;
}
