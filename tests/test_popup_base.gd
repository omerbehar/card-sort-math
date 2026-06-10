extends GdUnitTestSuite
## Tests for the shared modal pop-up chassis PopupBase (ADR-0006).

const POPUP_SCRIPT := preload("res://scenes/ui/popup_base.gd")


func _make() -> PopupBase:
	var p := PopupBase.new()
	add_child(p)        # _ready builds backdrop + body
	auto_free(p)
	return p


func test_root_and_backdrop_capture_input() -> void:
	var p := _make()
	assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var backdrop := p.find_child("Backdrop", true, false)
	assert_object(backdrop).is_not_null()
	assert_int((backdrop as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_body_is_available() -> void:
	var p := _make()
	assert_object(p.body()).is_not_null()


func test_is_always_processing() -> void:
	# Pop-ups must stay responsive even if a sibling pop-up pauses the tree.
	var p := _make()
	assert_int(p.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_close_emits_closed_and_frees() -> void:
	var p := _make()
	var fired: Array[bool] = [false]
	p.closed.connect(func() -> void: fired[0] = true)
	await p.close()
	assert_bool(fired[0]).is_true()
	await await_millis(40)   # let the deferred queue_free land
	assert_bool(is_instance_valid(p)).is_false()


func test_close_is_idempotent() -> void:
	var p := _make()
	var count: Array[int] = [0]
	p.closed.connect(func() -> void: count[0] += 1)
	# Fire two closes synchronously: the _closing guard must collapse them to a
	# single close (one `closed` emit, no error).
	p.close()
	p.close()
	await await_millis(220)   # past the close fade (_CLOSE_T) + free
	assert_int(count[0]).is_equal(1)
