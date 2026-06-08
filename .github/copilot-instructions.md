# Copilot Instructions — CardSortMath

CardSortMath is a **Godot 4.6** mobile game (card-sorting math gameplay) written
primarily in **GDScript**. Use these instructions when reviewing pull requests
and suggesting changes.

## Project conventions

- **Engine:** Godot 4.6, Mobile rendering method, Jolt Physics for 3D. Prefer
  APIs and patterns compatible with the Godot 4.x API (not Godot 3.x).
- **Line endings:** LF only. **Encoding:** UTF-8. Respect `.editorconfig`.
- **Ignored paths:** `.godot/`, `/android/`. Never suggest committing generated
  or build artifacts from these directories.
- Keep `.import` files in sync with their assets; don't hand-edit generated
  `uid://` values.

## GDScript style

- Use **static typing** wherever practical: typed variables (`var x: int`),
  typed function signatures, and typed return values (`func f() -> void:`).
- Follow the official GDScript style guide: `snake_case` for variables,
  functions, and file names; `PascalCase` for classes/nodes; `CONSTANT_CASE`
  for constants and enums.
- Prefer `@onready` over fetching nodes in `_ready()` when capturing node
  references.
- Use `class_name` for reusable types; prefer signals over polling for
  decoupling nodes.
- Prefer `@export` variables for editor-tunable values instead of hardcoded
  magic numbers.
- Avoid `get_node("...")`/`$` with long brittle paths; favor exported
  `NodePath`/node references or unique names (`%NodeName`).

## Review focus

- **Correctness:** off-by-one errors in card/sort logic, incorrect math
  comparisons, and edge cases (empty decks, ties, single card).
- **Null safety:** guard against `null` nodes/resources; check `is_instance_valid`
  before using freed nodes.
- **Performance (mobile):** flag per-frame allocations in `_process`/`_physics_process`,
  unnecessary node instantiation in hot paths, and heavy work that should be
  cached or precomputed. Mobile targets are resource-constrained.
- **Resource lifecycle:** ensure instanced scenes/nodes are freed with
  `queue_free()`; watch for signal connections that are never disconnected.
- **Scene/script coupling:** verify exported references and signal connections
  referenced in code actually exist in the corresponding `.tscn`.
- **Determinism:** card shuffling and math generation should be seedable/testable;
  flag hidden global state that makes behavior hard to reproduce.

## What to avoid suggesting

- Do not recommend Godot 3.x-only APIs or `yield` (use `await`).
- Do not suggest desktop-only features that break the Mobile renderer profile.
- Do not propose adding heavyweight dependencies without clear justification.

## Communication

- Keep review comments specific and actionable; reference the relevant node,
  script, or function. Prefer concrete code suggestions over general advice.
