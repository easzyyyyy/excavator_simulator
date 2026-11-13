@tool
class_name SoilParams
extends Resource
## Behaviour of one ground material. Defaults are common earth, dry packed, from the
## Caterpillar Performance Handbook tables (weight of materials, angle of repose,
## excavator bucket fill factors).
##
## Other materials, same tables and the same resistance equations (PLAN.md, section 8):
## data/clay.tres, clay in its natural bed, undrained cohesion 50 kPa (stiff clay);
## data/sand.tres, damp sand, friction 35 deg with a little cohesion from moisture.
##
## Volumes: ground in place is bank soil; once dug it swells into loose soil, which is
## what a bucket carries and what piles up when dumped.

## Name shown to the operator, in French.
@export var display_name := "terre"

@export_group("Density (kg/m3)")
## In place, undisturbed.
@export var bank_density := 1900.0
## Dug and loose. Bank over loose density gives the swell (handbook load factor 0.80).
@export var loose_density := 1510.0

@export_group("Slopes (deg)")
## Steepest slope of a pile of loose soil. The handbook gives 25 to 45 deg for moist
## common earth; this is the middle of the 30 to 35 deg cone the plan asks for.
@export var repose_angle_deg := 34.0
## Slope of the heap carried above the bucket strike-off plane. 45 deg is the SAE J296
## rating heap, which common earth reaches (handbook fill factor 100 to 110 % for
## moist loam).
@export var bucket_heap_angle_deg := 45.0

@export_group("Flow")
## Time constant of soil pouring over the bucket lip once the bucket tilts past what
## it can hold. Unsourced, tuned by eye.
@export var spill_time := 0.3

@export_group("Resistance (kPa)")
## Resistance of ground in place to the teeth and the cutting edge, per m2 of cut
## cross-section, for soil that flows into the bucket or past the teeth. The fundamental
## earthmoving equation gives about 45 kPa for cohesion 15 kPa, friction 30 deg and a
## 60 deg rake. The load weight is carried by the arm statics, not counted here.
@export var cutting_resistance := 45.0
## Pressure on a plate pushed sideways into ground in place, at the surface: Coulomb
## passive earth pressure for the same soil with the plate friction, from the cohesion.
@export var passive_pressure := 60.0
## Pressure under a plate pushed down into ground in place before it gives way, at the
## surface. Footing bearing capacity for the same soil in local shear, the failure of a
## plate that sinks in progressively (670 kPa in general shear).
@export var bearing_capacity := 290.0
## Growth of every resistance with depth, as a multiple of the weight of soil above the
## point (kPa per kPa of overburden): 2.4 for the cutting edge in the fundamental
## earthmoving equation, 3 for the passive pressure, 7 for the bearing capacity in local
## shear.
@export var overburden_factor := 3.0
## Loose soil resistance over ground in place: no cohesion, lower density (bearing and
## cutting from the same equations drop to 6 and 18 %).
@export var loose_resistance_ratio := 0.15
## Friction angle of soil sliding along the bucket steel: the soil-tool friction usually
## taken in the fundamental earthmoving equation (Vortex Studio default, 15 deg).
@export var plate_friction_deg := 15.0

@export_group("Look")
## Ground in place untouched and cut below its built height, and loose soil.
@export var ground_color := Color(0.42, 0.34, 0.25)
@export var dug_color := Color(0.35, 0.26, 0.18)
@export var loose_color := Color(0.29, 0.22, 0.15)
## Size of the grain drawn on dug and loose soil (m): fine for sand, clods for earth,
## large patches for clay.
@export var grain_scale := 0.11


## Loose volume gained per bank volume dug: 0.26 for common earth.
func swell() -> float:
	return bank_density / loose_density - 1.0
