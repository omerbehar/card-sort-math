class_name GeneratorFixtures
extends RefCounted
## Canonical [GeneratorParams] fixtures shared by the level-generator tests, so
## every "valid params" acceptance criterion means one concrete, named set
## (GDD level-generator §Acceptance Criteria). Flat-`tests/` adaptation of the
## GDD's `tests/unit/generator/generator_fixtures.gd`; CI scans `res://tests`
## recursively.


## { layout_id=0, D=4, R_min=3, R_max=12, max_operand=6 } — guarantees results
## with span 2 and span >= 4 are reachable, so operand-variety ACs are non-vacuous.
static func layout_0(seed: int = 0) -> GeneratorParams:
	return GeneratorParams.create(0, 4, 3, 12, 6, seed)


## { layout_id=1, D=5, R_min=3, R_max=16, max_operand=8 }.
static func layout_1(seed: int = 0) -> GeneratorParams:
	return GeneratorParams.create(1, 5, 3, 16, 8, seed)


## { layout_id=2, D=4, R_min=3, R_max=14, max_operand=7 }.
static func layout_2(seed: int = 0) -> GeneratorParams:
	return GeneratorParams.create(2, 4, 3, 14, 7, seed)


## All three fixtures at the given [param seed].
static func all(seed: int = 0) -> Array[GeneratorParams]:
	return [layout_0(seed), layout_1(seed), layout_2(seed)]
