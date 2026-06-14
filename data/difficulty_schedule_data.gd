class_name DifficultyScheduleData
extends Resource
## Data-driven difficulty schedule for the level generator (GDD level-generator
## §Tuning Knobs, ADR-0007). Maps a 1-based level index N to the generator's
## difficulty knobs. All values are [code]@export[/code] so a designer can retune
## the curve via a [code].tres[/code] / remote config without an app update; the
## defaults below encode the 5-band starting schedule.
##
## The pure [DifficultySchedule] interprets this data; it is a plain [Resource]
## ([RefCounted]) so [code]core/[/code] stays node-free. Every knob's step level is
## placed so that at most one of {R_max, D, layout_id, R_min, max_operand} changes
## on any single level (strict per-level stagger, AC-26).

# --- R_max(N): piecewise base + floor((N - anchor) / step_every), capped ---
# Parallel arrays, one entry per segment, evaluated in order (first N <= max_level).
# step_every == 0 means a flat segment (value == base).
@export var rmax_seg_max_level: Array[int] = [5, 12, 28, 52, 84, 2147483647]
@export var rmax_seg_base: Array[int] = [10, 10, 12, 16, 20, 23]
@export var rmax_seg_anchor: Array[int] = [0, 4, 12, 28, 52, 84]
@export var rmax_seg_step_every: Array[int] = [0, 2, 4, 6, 10, 20]
@export var rmax_seg_cap: Array[int] = [10, 12, 2147483647, 2147483647, 2147483647, 30]

# --- D (distinct results): base + one increment per step level <= N ---
@export var d_base: int = 4
@export var d_step_levels: Array[int] = [21]  # 4 -> 5 at N=21 (first hidden target)

# --- R_min: base + one increment per step level <= N ---
@export var rmin_base: int = 2
@export var rmin_step_levels: Array[int] = [15, 55, 87]  # -> 3, 4, 5

# --- max_operand: base, overridden by the last step value whose level <= N ---
@export var maxop_base: int = 6
@export var maxop_step_levels: Array[int] = [14, 31, 59, 91]
@export var maxop_step_values: Array[int] = [8, 10, 12, 15]

# --- layout: fixed per band up to cycle_start, then a held cycle ---
# The late-game cycle rotates through all six presets for variety. Adjacent
# entries (including the wrap) all differ, so a layout change lands on every
# cycle boundary — held at 4 levels these are levels 53, 57, 61, … (≡ 1 mod 4),
# which carry no other knob change, preserving the per-level stagger (AC-26).
@export var layout_band_max_level: Array[int] = [12, 28, 52]
@export var layout_band_value: Array[int] = [0, 2, 1]
@export var layout_cycle: Array[int] = [0, 3, 2, 4, 1, 5]
@export var layout_cycle_start: int = 53
@export var layout_cycle_hold: int = 4  # levels each cycle entry is held

@export var allow_queue_repeats: bool = true

# Spread equal targets apart in the generated queue: distinct starting decks and
# no two identical targets in a row. Off restores the legacy plain shuffle.
@export var space_queue_targets: bool = true

# --- recoverability (Core Rule 10 / AC-32) ---
@export var min_recovery_margin: int = 1
