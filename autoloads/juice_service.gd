extends Node
## Autoload (view/presentation layer): centralizes "juice" — haptic buzzes,
## particle bursts, and scale punches — all gated by [Settings].
##
## [code]reduced_motion[/code] disables the visual juice (bursts / punches);
## [code]haptics[/code] gates device vibration. Pure feel: the model never
## depends on this, and disabling motion must never change game outcomes — only
## presentation. The settings service is injectable (see [method configure]) so
## the gating is unit-testable. Implements Sprint 1 story S1-005.

# SettingsService; resolves to the autoload at runtime, injectable in tests.
var _settings = null


func _ready() -> void:
	if _settings == null:
		_settings = SettingsService


## Injects the settings service. Intended for tests.
func configure(settings: Object) -> void:
	_settings = settings


## True when visual motion (particles, scale punches, shake) is allowed.
func is_motion_enabled() -> bool:
	return _settings != null and not _settings.get_value("reduced_motion")


## True when device haptics are allowed.
func is_haptics_enabled() -> bool:
	return _settings != null and _settings.get_value("haptics")


## Fires a short device vibration (mobile), if haptics are enabled. A no-op on
## platforms without a vibrator (desktop / headless).
func haptic(duration_ms: int = 20) -> void:
	if is_haptics_enabled():
		Input.vibrate_handheld(duration_ms)


## Emits a one-shot particle burst at [param local_pos] under [param parent], if
## motion is enabled. Returns the emitter (which frees itself when finished) or
## null when motion is disabled. [param local_pos] is in [param parent]'s space.
func burst(parent: Node2D, local_pos: Vector2, color: Color = Color(1, 1, 1)) -> CPUParticles2D:
	if not is_motion_enabled() or parent == null:
		return null
	var particles := CPUParticles2D.new()
	particles.position = local_pos
	particles.one_shot = true
	particles.emitting = true
	particles.amount = 12
	particles.lifetime = 0.5
	particles.explosiveness = 0.9
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	particles.gravity = Vector2(0, 120)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = color
	parent.add_child(particles)
	particles.finished.connect(particles.queue_free)
	return particles


## Plays a quick scale "punch" (overshoot then settle) on [param node], if motion
## is enabled. No-op otherwise, so reduced-motion leaves the node untouched.
func punch(node: CanvasItem, amount: float = 0.15, duration: float = 0.18) -> void:
	if not is_motion_enabled() or node == null:
		return
	var base: Vector2 = node.scale
	var tween := node.create_tween()
	tween.tween_property(node, "scale", base * (1.0 + amount), duration * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", base, duration * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
