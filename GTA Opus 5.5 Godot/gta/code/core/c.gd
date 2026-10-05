class_name C
## Global constants shared by every system (collision layers, world dimensions, tuning).

# Collision layers (bit values)
const L_WORLD := 1
const L_PLAYER := 2
const L_NPC := 4
const L_VEHICLE := 8
const L_PROP := 16
const L_TRIGGER := 32
const L_PROJECTILE := 64
const L_RAGDOLL := 128

const MASK_CHAR_MOVE := L_WORLD | L_PROP            # what characters walk against (vehicles handled softly)
const MASK_VEHICLE := L_WORLD | L_VEHICLE | L_PROP | L_RAGDOLL
const MASK_BULLET := L_WORLD | L_PLAYER | L_NPC | L_VEHICLE | L_PROP | L_RAGDOLL
const MASK_SIGHT := L_WORLD | L_VEHICLE              # what blocks line of sight
const MASK_CAMERA := L_WORLD

# World
const SEA_LEVEL := 0.0
const LAND_Y := 1.0
const MAP_HALF := 300.0
const TERRAIN_HALF := 320.0
const TERRAIN_RES := 256            # cells per side (257 samples)

# Teams
enum Team { PLAYER, CIVILIAN, POLICE, GANG, ANIMAL }

# Surface types for impacts
const SURF_CONCRETE := "concrete"
const SURF_METAL := "metal"
const SURF_GLASS := "glass"
const SURF_WOOD := "wood"
const SURF_FLESH := "flesh"
const SURF_DIRT := "dirt"
const SURF_WATER := "water"
const SURF_GRASS := "grass"
