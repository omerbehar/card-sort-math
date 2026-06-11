---
paths:
  - "core/**"
  - "scenes/**"
---

# Gameplay Code Rules

- ALL gameplay values MUST come from external config/data files, NEVER hardcoded
- Use delta time for ALL time-dependent calculations (frame-rate independence)
- NO direct references to UI code — use events/signals for cross-system communication
- Every gameplay system must implement a clear interface
- State machines must have explicit transition tables with documented states
- Write unit tests for all gameplay logic — separate logic from presentation
- Document which design doc each feature implements in code comments
- No static singletons for game state — use dependency injection
- **Determinism in `core/`**: any randomness MUST use a caller-supplied seeded
  `RandomNumberGenerator`. NEVER call `Array.shuffle()`, `Array.pick_random()`,
  `randi()`/`randf()`, or other global-RNG APIs in `core/` — they draw from the engine's
  global RNG and silently break reproducibility (and the level-generator determinism tests,
  ADR-0007). Use a seeded Fisher–Yates helper instead. When re-seeding, set `rng.seed = …`
  (full reset), never `rng.state = …`.
- **No `load()`/`ResourceLoader` in `core/`**: `core/` is node-free and resource-free. An
  autoload (e.g. `LevelData`) loads the `.tres` and hands the typed `Resource`/`RefCounted`
  data to pure `core/` functions (ADR-0001, ADR-0007).

## Examples

**Correct** (seeded, deterministic):

```gdscript
func _fisher_yates_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)   # seeded RNG, reproducible
        var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
```

**Incorrect** (global RNG in `core/`):

```gdscript
slots.shuffle()                  # VIOLATION: global RNG, non-deterministic
var r: int = randi() % count     # VIOLATION: global RNG in core/
```

**Correct** (data-driven):

```gdscript
var damage: float = config.get_value("combat", "base_damage", 10.0)
var speed: float = stats_resource.movement_speed * delta
```

**Incorrect** (hardcoded):

```gdscript
var damage: float = 25.0   # VIOLATION: hardcoded gameplay value
var speed: float = 5.0      # VIOLATION: not from config, not using delta
```
