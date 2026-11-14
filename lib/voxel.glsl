#ifndef MRPIXEL_VOXEL
#define MRPIXEL_VOXEL

// Volumen de vóxeles centrado en la cámara (VOXEL_SIZE^3). Slots de voxelImg en X:
// 0: flags, ID (bits 8-15), nivel de luz (16-19)
// 1-6: textura de cada cara (arriba, abajo, norte, sur, este, oeste)
// 7: tinte del bioma; 8: capa con huecos de los laterales (pasto)
// 9: brillo de textura (packPbrGlow)

#define VOX_SOLID 1u
#define VOX_GEOMETRY 2u
#define VOX_EMITTER 4u
#define VOX_TINT 8u
#define VOX_LEAVES 16u
#define VOX_WATER 32u
#define VOX_XP 64u   // orbe de experiencia
#define VOX_PBRGLOW 128u   // textura que brilla (slot 9)
#define VOX_PARTIAL (1u << 20u)   // losa, escalera...
#define VOX_THIN (1u << 21u)   // vena de sculk, alfombra

bool voxelFullCube(uint d) { return (d & VOX_SOLID) != 0u && (d & (VOX_PARTIAL | VOX_THIN)) == 0u; }

#define SLOT_DATA 0
#define SLOT_FACE 1      // + cara (faceIndex)
#define SLOT_TINT 7
#define SLOT_OVERLAY 8
#define SLOT_GLOW 9

ivec3 slotCoord(ivec3 v, int slot) { return ivec3(v.x + slot * VOXEL_SIZE, v.y, v.z); }

bool inVoxelVolume(ivec3 v) {
    return all(greaterThanEqual(v, ivec3(0))) && all(lessThan(v, ivec3(VOXEL_SIZE)));
}

ivec3 playerToVoxel(vec3 p) { return ivec3(floor(p + cameraPositionFract)) + VOXEL_HALF; }

// Cara según la normal: 0 arriba, 1 abajo, 2 norte (-z), 3 sur (+z), 4 este (+x), 5 oeste (-x)
int faceIndex(vec3 n) {
    vec3 a = abs(n);
    if (a.y >= a.x && a.y >= a.z) return n.y > 0.0 ? 0 : 1;
    if (a.z >= a.x) return n.z < 0.0 ? 2 : 3;
    return n.x > 0.0 ? 4 : 5;
}

// Textura de una cara: esquina en el atlas (13 + 13 bits), log2 del tamaño (4), tinte (1), tupida (1). 0 = sin
// textura
uint packFaceSprite(ivec2 minT, int log2Size, bool tinted, bool dense) {
    return uint(minT.x) | (uint(minT.y) << 13u) | (uint(log2Size) << 26u) | (tinted ? (1u << 30u) : 0u) | (dense ? (1u << 31u) : 0u);
}

// Brillo de textura: nivel en los bits altos (atomicMax) y color normalizado
uint packPbrGlow(int level, vec3 color) { return (uint(clamp(level, 0, 15)) << 24u) | (packUnorm4x8(vec4(color, 0.0)) & 0xFFFFFFu); }
int pbrGlowLevel(uint w) { return int(w >> 24u); }
vec3 pbrGlowColor(uint w) { return unpackUnorm4x8(w & 0xFFFFFFu).rgb; }

const vec3 END_CRYSTAL_LIGHT = vec3(0.70, 0.15, 1.00);
#define VOX_CRYSTAL (1u << 24u)   // cristal del End (sólo luz)
#define VOX_FIRE (1u << 25u)   // entidad que arde (sólo luz)
const vec3 ENTITY_FIRE_LIGHT = vec3(1.00, 0.60, 0.26);
#define FIRE_LIGHTS 16   // sin floodfill: entidades que arden (fireLightImg)

// ------------------------------------------------------- según el ID -------
bool idIsPlant(int id) { return id >= 1 && id <= 9; }

// IDs que pueden ser sólidos
bool idCanBeSolid(int id) {
    if (id >= 1 && id <= 15) return false;   // plantas, hojas, agua, cristal, hielo, slime, portal, lava
    if (id >= 20 && id <= 35) return false;  // cristal tintado
    return true;
}

bool idIsTinted(int id) {
    return (id >= 20 && id <= 35) || id == 12 || id == 13;
}

vec3 tintColor(int id) {
    if (id == 12) return vec3(0.75, 0.88, 1.00);
    if (id == 13) return vec3(0.60, 1.00, 0.50);
    int c = id - 20;
    if (c == 0) return vec3(0.95);
    if (c == 1) return vec3(1.00, 0.55, 0.15);
    if (c == 2) return vec3(0.85, 0.30, 0.85);
    if (c == 3) return vec3(0.45, 0.70, 1.00);
    if (c == 4) return vec3(1.00, 0.90, 0.25);
    if (c == 5) return vec3(0.55, 0.90, 0.20);
    if (c == 6) return vec3(1.00, 0.55, 0.70);
    if (c == 7) return vec3(0.35);
    if (c == 8) return vec3(0.65);
    if (c == 9) return vec3(0.20, 0.65, 0.75);
    if (c == 10) return vec3(0.55, 0.25, 0.85);
    if (c == 11) return vec3(0.20, 0.30, 0.95);
    if (c == 12) return vec3(0.50, 0.33, 0.20);
    if (c == 13) return vec3(0.35, 0.55, 0.15);
    if (c == 14) return vec3(0.85, 0.20, 0.20);
    if (c == 15) return vec3(0.10);
    return vec3(1.0);
}

// Amatista: 80 + tamaño * 6 + cara
bool idIsAmethyst(int id) { return id >= 80 && id <= 103; }

// Sculk (63) y sus bloques con luz (50)
bool idIsSculk(int id) { return id == 63 || id == 50; }
float textureGlowScale(int id) { return idIsSculk(id) ? SCULK_GLOW : 1.0; }

// Antorchas: 110 + tipo * 5 + colocación. Tipo: 0 normal, 1 almas, 2 redstone, 3 cobre
bool idIsTorch(int id) { return id >= 110 && id <= 129; }
int torchLightId(int id) { return int[4](40, 41, 42, 54)[(id - 110) / 5]; }

bool idIsEmitter(int id) {
    return id == 9 || id == 14 || id == 15 || (id >= 40 && id <= 62) || idIsAmethyst(id) || idIsTorch(id);
}

// Color de la luz de cada bloque
vec3 emitterColor(int id) {
    if (idIsTorch(id)) id = torchLightId(id);
    if (id == 15) return vec3(1.00, 0.40, 0.08);   // lava
    if (id == 14) return vec3(0.75, 0.25, 1.30);   // portal del Nether
    if (id == 40) return vec3(1.00, 0.60, 0.26);   // antorcha, farol
    // fuego; en el End, morado
    if (id == 62) return isEnd() ? END_CRYSTAL_LIGHT : vec3(1.00, 0.60, 0.26);
    if (id == 41) return vec3(0.22, 0.80, 1.00);   // almas
    if (id == 42) return vec3(1.00, 0.14, 0.05);   // redstone
    if (id == 43) return vec3(1.00, 0.35, 0.08);   // magma
    if (id == 44) return vec3(1.00, 0.80, 0.45);   // piedra luminosa
    if (id == 45) return vec3(0.55, 0.90, 1.00);   // linterna de mar
    if (id == 46) return vec3(0.95, 0.92, 1.00);   // vara del End
    if (idIsAmethyst(id)) return vec3(0.95, 0.42, 0.92);   // amatista
    if (id == 9) return vec3(0.80, 1.00, 0.35);    // luciérnagas
    if (id == 48) return vec3(0.60, 0.25, 1.00);   // obsidiana llorona
    if (id == 49) return vec3(0.45, 1.00, 0.75);   // liquen luminoso
    if (id == 50) return vec3(0.15, 0.75, 0.90);   // sculk
    if (id == 51) return vec3(1.00, 0.55, 0.85);   // ranaluz perla
    if (id == 52) return vec3(0.50, 1.00, 0.55);   // ranaluz verde
    if (id == 53) return vec3(1.00, 0.85, 0.45);   // ranaluz ocre
    if (id == 54) return vec3(0.45, 1.00, 0.55);   // cobre
    if (id == 55) return vec3(1.00, 0.55, 0.20);   // hornos
    if (id == 56) return vec3(1.00, 0.65, 0.35);   // velas
    if (id == 57) return vec3(0.75, 0.55, 1.00);   // mesa de encantamientos, End
    if (id == 58) return vec3(1.00, 0.55, 0.20);   // corazón de crepitante, spawner
    if (id == 59) return vec3(1.00, 0.72, 0.42);   // bombilla de cobre
    if (id == 60) return vec3(0.50, 1.00, 0.70);   // pepino de mar
    if (id == 61) return vec3(1.00, 0.75, 0.35);   // bayas luminosas
    return vec3(1.00, 0.75, 0.50);
}

const vec3 XP_LIGHT_COLOR = vec3(0.55, 1.00, 0.20);

int emitterDefaultLevel(int id) {
    if (idIsTorch(id)) id = torchLightId(id);
    if (id == 15 || id == 44 || id == 45 || id == 51 || id == 52 || id == 53 || id == 55) return 15;
    if (id == 62) return 15;
    if (id == 40 || id == 54 || id == 46 || id == 61) return 14;
    if (id == 14) return 13;
    if (id == 41) return 10;
    if (id == 48 || id == 57) return 10;
    if (id == 42 || id == 49 || id == 50) return 7;
    if (id == 9) return 2;
    if (id == 43 || id == 56) return 3;
    if (idIsAmethyst(id)) return int[4](5, 4, 2, 1)[(id - 80) / 6];   // racimo, brote grande, mediano, pequeño
    if (id == 60) return 6;
    if (id == 58 || id == 59) return 12;
    return 0;
}

// Ocupación para la luz del sol en el follaje: x hojas, y sólido
vec2 foliageOcc(uint d) {
    if ((d & VOX_LEAVES) != 0u) return vec2(1.0, 0.0);
    return vec2(0.0, float((d & VOX_SOLID) != 0u && (d & VOX_THIN) == 0u));
}

// ----------------------------------------------------------- lectura -------
#ifdef VOXEL_READ

uniform usampler3D voxelSampler;
uniform sampler3D lightSamplerA;
uniform sampler3D lightSamplerB;
uniform sampler3D lightDirSampler;

uint voxelData(ivec3 v) { return texelFetch(voxelSampler, v, 0).r; }
uint voxelSlot(ivec3 v, int slot) { return texelFetch(voxelSampler, slotCoord(v, slot), 0).r; }

bool voxelBlocksLight(uint d) { return (d & VOX_SOLID) != 0u && (d & VOX_EMITTER) == 0u; }

vec3 voxelLight(ivec3 v) {
    // A en frames pares, B en impares
    if ((frameCounter & 1) == 0) return texelFetch(lightSamplerA, v, 0).rgb;
    return texelFetch(lightSamplerB, v, 0).rgb;
}

// Floodfill en pos, trilineal sin los vóxeles sólidos. dirOut: dirección hacia la luz. Devuelve el peso (0 fuera del
// volumen)
float sampleFloodfill(vec3 pos, vec3 n, out vec3 lightOut, out vec3 dirOut) {
    lightOut = vec3(0.0);
    dirOut = vec3(0.0);

    vec3 p = pos + cameraPositionFract + n * 0.5 + float(VOXEL_HALF) - 0.5;
    ivec3 b = ivec3(floor(p));
    vec3 f = p - vec3(b);
    if (any(lessThan(b, ivec3(1))) || any(greaterThanEqual(b, ivec3(VOXEL_SIZE - 2)))) return 0.0;

    // dirección por vóxel, interpolada igual
    vec3 acc = vec3(0.0);
    vec3 dacc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 8; i++) {
        ivec3 o = ivec3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        ivec3 v = b + o;
        if (voxelBlocksLight(voxelData(v))) continue;
        vec3 w3 = mix(1.0 - f, f, vec3(o));
        float w = w3.x * w3.y * w3.z;
        acc += voxelLight(v) * w;
        dacc += texelFetch(lightDirSampler, v, 0).xyz * w;
        wsum += w;
    }
    if (wsum < 1e-4) return 0.0;
    lightOut = acc / wsum;
    dirOut = dacc / wsum;

    float d = max3(abs(vec3(b) - float(VOXEL_HALF)));
    return 1.0 - smoothstep(float(VOXEL_HALF) - 12.0, float(VOXEL_HALF) - 3.0, d);
}

// Vóxeles que paran la lluvia
bool voxelBlocksRain(uint d) {
    if ((d & (VOX_SOLID | VOX_LEAVES | VOX_TINT | VOX_WATER)) != 0u) return true;
    if ((d & VOX_GEOMETRY) == 0u) return false;
    if ((d & VOX_EMITTER) != 0u) return false;
    int id = int((d >> 8u) & 255u);
    return !idIsPlant(id);
}

#endif // VOXEL_READ

#endif
