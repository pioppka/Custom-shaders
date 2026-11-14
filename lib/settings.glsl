// MrPixel Shaders - opciones

// ------------------------------------------------------------ Color y estilo ---
#define EXPOSURE 1.00 // [0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.35 1.50 1.75 2.00 2.50 3.00]
#define CONTRAST 1.05 // [0.90 0.95 1.00 1.05 1.10 1.15 1.20]
#define SATURATION 1.15 // [0.80 0.90 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define VIBRANCE 1.20 // [1.00 1.10 1.20 1.30 1.40 1.50]
#define ALBEDO_SATURATION 1.10 // [1.00 1.05 1.10 1.15 1.20 1.30]
#define VIGNETTE 0.15 // [0.00 0.10 0.15 0.20 0.30 0.40]
#define LOADING_TITLE
#define IMPACT_FRAMES
#define IMPACT_RANGE 16 // [8 12 16 24 32]
//#define DOF
#define DOF_STRENGTH 16 // [8 12 16 24 32 48]

// --------------------------------------------------------------- Iluminación ---
#define SUN_BRIGHTNESS 1.00 // [0.60 0.80 1.00 1.20 1.40 1.60 2.00]
#define AMBIENT_BRIGHTNESS 1.00 // [0.40 0.60 0.80 1.00 1.20 1.40 1.70 2.00]
#define NIGHT_BRIGHTNESS 1.00 // [0.50 0.75 1.00 1.50 2.00 3.00]
#define MIN_LIGHT 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define BLOCKLIGHT_BRIGHTNESS 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00]
#define EMISSIVE_BRIGHTNESS 3.00 // [1.00 2.00 3.00 4.00 6.00 8.00]
#define VANILLA_AO
const float ambientOcclusionLevel = 1.0;
#define LEAF_SSS
#define LEAF_SSS_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00 3.00]

// ------------------------------------------------------------------- Sombras ---
#define SHADOWS
const int shadowMapResolution = 2048; // [256 512 1024 2048 4096]
// múltiplos de 32 (lib/shadows.glsl)
const float shadowDistance = 128.0; // [64.0 96.0 128.0 160.0 192.0 256.0]
const float shadowDistanceRenderMul = 1.0;
#define PIXEL_SHADOW_SCALE 1.0 // [0.25 0.5 1.0]
#define COLORED_SHADOWS
const float sunPathRotation = -25.0; // [-50.0 -40.0 -30.0 -25.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0]

// -------------------------------------------------- Luz de color (floodfill) ---
//#define FLOODFILL
#define TINTED_LIGHT
#define FLOODFILL_BRIGHTNESS 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00 3.00]
#define FLOODFILL_FALLOFF 0.86 // [0.80 0.83 0.86 0.88 0.90 0.92]
// chunks que siempre van al pase de sombras (shadow.culling = safe_zone)
const float voxelDistance = 64.0;

// -------------------------------------------------------------------- Bordes ---
// EDGE_COLOR: 0 luz, 1 blanco, 2 bloque; BACKLIGHT_TINT: 0 luz, 1 bloque, 2 blanco
#define LIGHT_EDGES
#define EDGE_STRENGTH 0.60 // [0.20 0.40 0.60 0.80 1.00 1.30 1.60]
#define EDGE_WIDTH 1.0 // [1.0 1.5 2.0 2.5 3.0 4.0]
#define EDGE_COLOR 0 // [0 1 2]
#define BLOCKLIGHT_RIM 1.00 // [0.00 0.50 1.00 1.50 2.00]
#define EDGE_LEAVES 0 // [0 1 2]
#define BACKLIGHT
#define BACKLIGHT_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00 3.00]
#define BACKLIGHT_WIDTH 1.5 // [1.0 1.5 2.0 2.5 3.0 4.0]
#define BACKLIGHT_TINT 0 // [0 1 2]
#define BACKLIGHT_BLOCKLIGHT 1.00 // [0.00 0.50 1.00 1.50 2.00]

// ---------------------------------------------------------- Glow y destellos ---
#define BLOOM
#define BLOOM_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
#define BLOOM_THRESHOLD 0.90 // [0.50 0.70 0.90 1.10 1.40 1.80]
#define BLOOM_PIXEL_SIZE 8 // [0 4 6 8 10 12 16 20 24 32]
#define BLOOM_STEPS 0 // [0 3 4 6 8 12]
#define LENS_FLARE
#define FLARE_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00]
#define FLARE_PIXEL_SIZE 6 // [2 4 6 8 10 12 16]

// ----------------------------------------------------- Reflejos y refracción ---
#define REFLECTION_MODE 1 // [0 1 2]
#define REFLECTION_PIXELS 16 // [0 4 8 16 32]
#define RT_STEPS 96 // [32 48 64 96 128 192]
#define SMOOTH_REFLECTIONS
#define SKY_REFLECTIONS
//#define PLASTIC_REFLECTIONS
#define PLASTIC_REFL_STRENGTH 0.60 // [0.20 0.40 0.60 0.80 1.00 1.30]
#define PLASTIC_REFL_BLUR 16 // [6 10 16 24 32]
#define REFRACTION
#define REFRACTION_PIXELS 16 // [4 8 16 32]
#define REFRACTION_STRENGTH 1.00 // [0.00 0.50 1.00 1.50 2.00 3.00]

// ---------------------------------------------------------------------- Agua ---
#define WATER_STYLE 0 // [0 1 2]
#define WATER_ALPHA 0.55 // [0.30 0.40 0.50 0.55 0.65 0.75 0.85]
#define WATER_REFLECTIVITY 1.00 // [0.25 0.50 0.75 1.00 1.25]
#define WATER_SPARKLE
#define WATER_WAVES
#define WAVE_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00]
#define WATER_PIXELS 16 // [8 16 32]
#define WATER_FOAM
#define SHORE_FOAM_WIDTH 1.00 // [0.50 0.75 1.00 1.50 2.00]
// rejilla de la espuma
const float FOAM_PIXELS = 16.0;
#define WATER_SIM
#define RIPPLE_STRENGTH 1.00 // [0.50 0.75 1.00 1.50 2.00 3.00]
#define RIPPLE_FOAM 1.00 // [0.00 0.50 1.00 1.50 2.00]
#define RIPPLE_DURATION 0.980 // [0.950 0.965 0.980 0.987 0.993]
#define WATER_SIM_SIZE 1024   // ligado a shaders.properties y shadowcomp2
#define WATER_CAUSTICS
#define CAUSTICS_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00]
#define UNDERWATER_FOG 0.25 // [0.10 0.25 0.50 0.75 1.00]

// -------------------------------------------------------------------- Lluvia ---
#define RAIN_PUDDLES
#define PUDDLE_COVERAGE 100 // [10 20 30 40 50 60 70 80 90 100]
#define PUDDLE_PIXELS 16 // [4 8 16]
#define RAIN_RIPPLES
#define RAIN_CAMERA_FOG 1.00 // [0.00 0.50 1.00 1.50 2.00 3.00]
const float wetnessHalflife = 200.0;
const float drynessHalflife = 400.0;

// ------------------------------------------------------------ Cielo y niebla ---
#define CARTOON_CLOUDS
#define CLOUD_RIM
#define CLOUD_RIM_STRENGTH 1.00 // [0.50 0.75 1.00 1.50 2.00 3.00]
#define SUN_BRIGHTNESS_SKY 10.0 // [4.0 6.0 8.0 10.0 14.0 20.0]
#define MOON_BRIGHTNESS_SKY 5.0 // [1.0 2.0 3.0 5.0 7.0 10.0 14.0]
#define STARS
#define STAR_BRIGHTNESS 10.0 // [2.0 4.0 6.0 8.0 10.0 14.0 20.0 30.0]
#define FOG_DENSITY 1.00 // [0.00 0.25 0.50 0.75 1.00 1.50 2.00 3.00]
#define BORDER_FOG

// ------------------------------------------------- Niebla de suelo (deep dark) ---
// necesita FLOODFILL
#define GROUND_FOG
#define GROUND_FOG_DENSITY 0.75 // [0.50 0.75 1.00 1.50 2.00 3.00]
#define GROUND_FOG_HEIGHT 0.50 // [0.50 0.75 1.00 1.50 2.00 3.00]
#define GROUND_FOG_SPEED 1.00 // [0.50 1.00 1.50 2.00 3.00]
#define GROUND_FOG_BRIGHTNESS 0.50 // [0.25 0.50 0.75 1.00 1.50 2.00]
// mitad del ancho en bloques (imágenes de shaders.properties y shadowcomp3)
#define GROUND_FOG_DISTANCE 48 // [32 48 64]

// ------------------------------------------------------- Bloques y entidades ---
#define WAVING_PLANTS
#define WAVING_LEAVES
#define WAVING_SPEED 1.00 // [0.50 0.75 1.00 1.50 2.00]
#define PORTAL_EMISSIVE
#define PORTAL_BRIGHTNESS 2.50 // [1.00 1.50 2.00 2.50 3.00 4.00 5.00]
#define XP_ORB_GLOW
#define XP_ORB_BRIGHTNESS 3.00 // [1.50 2.00 3.00 4.00 6.00]
#define XP_ORB_LIGHT 8 // [4 6 8 10 12 15]

// -------------------------------------------------------------- Texturas PBR ---
#define PBR_NORMALS
#define NORMAL_STRENGTH 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50]
#define PBR_SPECULAR
#define PBR_EMISSIVE
#define PBR_GLOW_LIGHT 4 // [0 2 3 4 5 6 8]
#define SCULK_GLOW 0.30 // [0.00 0.15 0.30 0.50 0.75 1.00]

// ------------------------------------------------------------ Supervivencia ---
#define LIGHT_METER 2 // [0 1 2]

// --------------------------------------------------------------------- Debug ---
//#define WHITE_WORLD
#define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7]
//#define SSS_GLOBAL
//#define PLAYER_STUDIO_LIGHT
//#define SSS_ALL_BLOCKS
#define IMPACT_DEBUG 0 // [0 1 2]
#define IMPACT_POLARITY 0 // [0 1 2]
#define IMPACT_THRESHOLD 0.60 // [0.30 0.40 0.50 0.60 0.70 0.80 1.00 1.20]
#define IMPACT_DURATION 0.10 // [0.08 0.10 0.12 0.15 0.20 0.25 0.30 0.40 0.50 0.75 1.00]
// segundos tras uno antes de que pueda empezar otro
#define IMPACT_COOLDOWN 0.30 // [0.00 0.10 0.20 0.30 0.50 0.75 1.00 1.50 2.00 3.00]
#define IMPACT_LINES 220 // [80 120 160 220 300 400]
#define IMPACT_FLASH 0.04 // [0.00 0.04 0.08 0.12 0.16]
#define IMPACT_LINE_CHANCE 60 // [20 30 40 50 60 70 80 90]
#define IMPACT_LINE_RATE 30 // [0 10 15 20 30 60]
#define IMPACT_LINE_WIDTH 0.70 // [0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define IMPACT_INNER 0.12 // [0.00 0.05 0.12 0.20 0.30 0.40]

// ------------------------------------------------------- Constantes internas ---
#define VOXEL_SIZE 128
#define VOXEL_HALF 64
