#ifndef MRPIXEL_SUNSHADOW
#define MRPIXEL_SUNSHADOW

// Sombra del sol: bloques con un rayo por los vóxeles; entidades, hojas, plantas, cristal y lo lejano con el mapa.
// Sin rayo donde el mapa no ve nada alrededor. Requiere: sky, shadows (SHADOW_SAMPLING), voxel (VOXEL_READ)

#if defined SHADOW_SAMPLING && defined VOXEL_READ

const float SUN_VOXEL_DIST = 24.0;   // bloques

#ifdef VOX_SHAPE
bool sunShaped(uint d) { return (d & VOX_SHAPE) != 0u && (d & VOX_LEAVES) == 0u && !voxelFullCube(d); }
#endif

// ¿Lo que tapa en P lo resuelven los vóxeles?
bool sunOccluderInVoxels(vec3 P, vec3 L) {
    ivec3 v = playerToVoxel(P - L * 0.05);
    if (!inVoxelVolume(v)) return false;
    uint d = voxelData(v);
    if ((d & VOX_LEAVES) != 0u) return false;
#ifdef VOX_SHAPE
    if (sunShaped(d)) return true;
#endif
    return voxelFullCube(d);
}

// Rayo hacia la luz desde p (coordenadas del volumen). endP: hasta dónde llegó
bool sunVoxelBlocked(vec3 p, vec3 dir, out vec3 endP) {
    endP = p + dir * SUN_VOXEL_DIST;
    ivec3 cell = ivec3(floor(p));
    ivec3 stepI = ivec3(sign(dir));
    vec3 invDir = 1.0 / max(abs(dir), vec3(1e-6));
    vec3 fr = p - vec3(cell);
    vec3 tMax = vec3(
        stepI.x > 0 ? (1.0 - fr.x) * invDir.x : (stepI.x < 0 ? fr.x * invDir.x : 1e30),
        stepI.y > 0 ? (1.0 - fr.y) * invDir.y : (stepI.y < 0 ? fr.y * invDir.y : 1e30),
        stepI.z > 0 ? (1.0 - fr.z) * invDir.z : (stepI.z < 0 ? fr.z * invDir.z : 1e30));
#ifdef VOX_SHAPE
    // forma del propio vóxel
    float th;
    int sa;
    if (sunShaped(voxelData(cell)) && shapeHit(voxelShapeIndex(cell), fr, dir, true, th, sa)) return true;
#endif
    for (int i = 0; i < 48; i++) {
        float t;
        if (tMax.x < tMax.y && tMax.x < tMax.z) {
            cell.x += stepI.x; t = tMax.x; tMax.x += invDir.x;
        } else if (tMax.y < tMax.z) {
            cell.y += stepI.y; t = tMax.y; tMax.y += invDir.y;
        } else {
            cell.z += stepI.z; t = tMax.z; tMax.z += invDir.z;
        }
        if (t > SUN_VOXEL_DIST) return false;
        if (!inVoxelVolume(cell)) {
            endP = p + dir * t;
            return false;
        }
        uint d = voxelData(cell);
        if ((d & VOX_LEAVES) != 0u) continue;
        if (voxelFullCube(d)) return true;
#ifdef VOX_SHAPE
        if (sunShaped(d) && shapeHit(voxelShapeIndex(cell), clamp(p + dir * t - vec3(cell), 0.0, 1.0), dir, false, th, sa)) return true;
#endif
    }
    return false;
}

// Sombra del mapa sin lo que ya miran los vóxeles
float sunMapDetail(vec3 s, vec3 L) {
    float res = float(shadowMapResolution);
    ivec2 i = clamp(ivec2(s.xy * res), ivec2(0), ivec2(shadowMapResolution - 1));
    float z = texelFetch(shadowtex1, i, 0).r;
    if (s.z <= z) return 1.0;
    return sunOccluderInVoxels(shadowTexelPlayer((vec2(i) + 0.5) / res, z), L) ? 1.0 : 0.0;
}

// pos: espacio jugador (ya en la rejilla de píxeles); geoNormal: normal geométrica
vec3 getSunShadow(vec3 pos, vec3 geoNormal) {
#ifndef SHADOWS
    return vec3(1.0);
#else
    vec3 s;
    float fade;
    if (!shadowCoords(pos, geoNormal, s, fade)) return vec3(1.0);
    vec3 p = pos + geoNormal * 0.02 + cameraPositionFract + float(VOXEL_HALF);
    if (!inVoxelVolume(ivec3(floor(p)))) return mix(shadowFromMap(s), vec3(1.0), fade);

    // nada en los 4x4 texels de alrededor: al sol
    float res = float(shadowMapResolution);
    vec2 c0 = floor(s.xy * res - 0.5);
    vec4 zm = min(min(textureGather(shadowtex1, c0 / res), textureGather(shadowtex1, (c0 + vec2(2.0, 0.0)) / res)),
                  min(textureGather(shadowtex1, (c0 + vec2(0.0, 2.0)) / res), textureGather(shadowtex1, (c0 + 2.0) / res)));
    if (min(min(zm.x, zm.y), min(zm.z, zm.w)) >= s.z) return mix(shadowFromMap(s), vec3(1.0), fade);

    vec3 L = lightDirWorld();
    vec3 endP;
    vec3 result = vec3(0.0);
    if (!sunVoxelBlocked(p, L, endP)) {
        float detail = sunMapDetail(s, L);
        result = detail * shadowGlassTint(s, shadowTest(shadowtex1, s));
        // lo que tapa más allá del rayo
        if (detail > 0.001) result *= getShadow(endP - cameraPositionFract - float(VOXEL_HALF), L);
    }
    return mix(result, vec3(1.0), fade);
#endif
}

#endif
#endif
