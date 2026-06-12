extends GdUnitTestSuite
## Tests for the WalletService transaction core (S3-004).
##
## WalletService is instantiated directly (NOT via the autoload) and configured with
## injected stubs — a fake save, a FixedTimeProvider, and an EconomyConfig — so every
## test is isolated and proves the logic has no autoload coupling (DI over singletons).
## Emitted [EconomyEvent]s are captured for assertion.

const WALLET := preload("res://autoloads/wallet_service.gd")

const COINS := EconomyEnums.Currency.COINS
const GEMS := EconomyEnums.Currency.GEMS
const LEVEL_WIN := EconomyEnums.EarnSource.LEVEL_WIN

# A minimal stand-in for SaveService: real SaveData, a counted save_game(), no file I/O.
class StubSave extends RefCounted:
	var data: SaveData
	var save_called: int = 0
	func _init() -> void:
		data = SaveData.new()
	func save_game() -> void:
		save_called += 1


var _events: Array = []
var _save_stub: StubSave


# Builds a configured WalletService seeded to the given balances. Optionally takes a
# config override (e.g. a small coins_max for cap tests). Captures emitted events.
func _make(coins: int = 0, gems: int = 0, config: EconomyConfig = null):
	_events = []
	_save_stub = StubSave.new()
	_save_stub.data.wallet_coins = coins
	_save_stub.data.wallet_gems = gems
	var cfg: EconomyConfig = config if config != null else EconomyConfig.new()
	var svc = auto_free(WALLET.new())
	svc.configure(_save_stub, null, FixedTimeProvider.new(), cfg)
	svc.economy_event.connect(func(e: EconomyEvent) -> void: _events.append(e))
	return svc


func _last() -> EconomyEvent:
	return _events.back() if not _events.is_empty() else null


func _event_of(kind: int) -> EconomyEvent:
	for e in _events:
		if e.kind == kind:
			return e
	return null


func _config_with_coins_max(cap: int) -> EconomyConfig:
	var cfg := EconomyConfig.new()
	cfg.coins_max = cap
	return cfg


# --- spend ---

func test_spend_success_deducts_and_emits() -> void:
	var w = _make(100)
	var ok: bool = w.spend(COINS, 30)
	assert_bool(ok).is_true()
	assert_int(w.balance(COINS)).is_equal(70)
	var e := _last()
	assert_int(e.kind).is_equal(EconomyEvent.Kind.CURRENCY_SPENT)
	assert_int(e.currency).is_equal(COINS)
	assert_int(e.amount).is_equal(30)
	assert_int(e.new_balance).is_equal(70)


func test_spend_insufficient_returns_false_and_emits_spend_failed() -> void:
	var w = _make(20)
	var ok: bool = w.spend(COINS, 30)
	assert_bool(ok).is_false()
	assert_int(w.balance(COINS)).is_equal(20)
	var e := _last()
	assert_int(e.kind).is_equal(EconomyEvent.Kind.SPEND_FAILED)
	assert_int(e.amount).is_equal(30)
	assert_int(e.new_balance).is_equal(20)  # reports current balance at failure


func test_spend_at_zero_balance_fails() -> void:
	var w = _make(0)
	assert_bool(w.spend(COINS, 1)).is_false()
	assert_int(w.balance(COINS)).is_equal(0)
	assert_int(_last().kind).is_equal(EconomyEvent.Kind.SPEND_FAILED)


func test_spend_zero_amount_returns_false_with_no_event() -> void:
	var w = _make(100)
	assert_bool(w.spend(COINS, 0)).is_false()
	assert_int(w.balance(COINS)).is_equal(100)
	assert_int(_events.size()).is_equal(0)  # logic-error guard, EC-14


func test_spend_negative_amount_returns_false_with_no_event() -> void:
	var w = _make(100)
	assert_bool(w.spend(COINS, -5)).is_false()
	assert_int(_events.size()).is_equal(0)


func test_spend_persists_to_save() -> void:
	var w = _make(100)
	w.spend(COINS, 30)
	assert_int(_save_stub.save_called).is_greater_equal(1)
	assert_int(_save_stub.data.wallet_coins).is_equal(70)


# --- earn ---

func test_earn_credits_and_emits() -> void:
	var w = _make(400)
	var actual: int = w.earn(COINS, 55, LEVEL_WIN)
	assert_int(actual).is_equal(55)
	assert_int(w.balance(COINS)).is_equal(455)
	var e := _last()
	assert_int(e.kind).is_equal(EconomyEvent.Kind.CURRENCY_EARNED)
	assert_int(e.amount).is_equal(55)
	assert_int(e.source).is_equal(LEVEL_WIN)
	assert_int(e.new_balance).is_equal(455)


func test_earn_clamps_at_cap_and_returns_actual_credited() -> void:
	var w = _make(990, 0, _config_with_coins_max(1000))
	var actual: int = w.earn(COINS, 100, LEVEL_WIN)
	assert_int(actual).is_equal(10)               # only 10 fit under the cap
	assert_int(w.balance(COINS)).is_equal(1000)
	assert_int(_last().amount).is_equal(10)        # event reports actual credited


func test_earn_zero_amount_no_mutation_no_event() -> void:
	var w = _make(100)
	assert_int(w.earn(COINS, 0, LEVEL_WIN)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(100)
	assert_int(_events.size()).is_equal(0)


func test_earn_at_cap_credits_nothing_no_event() -> void:
	var w = _make(1000, 0, _config_with_coins_max(1000))
	assert_int(w.earn(COINS, 50, LEVEL_WIN)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(1000)
	assert_int(_events.size()).is_equal(0)


func test_earn_one_below_cap_credits_one() -> void:
	var w = _make(999, 0, _config_with_coins_max(1000))
	assert_int(w.earn(COINS, 2, LEVEL_WIN)).is_equal(1)
	assert_int(w.balance(COINS)).is_equal(1000)


# --- atomic rollback (EC-09) ---

func test_spend_with_failed_action_rolls_back_via_snapshot() -> void:
	var w = _make(100)
	var fail := func() -> bool: return false
	var ok: bool = w.spend(COINS, 50, fail)
	assert_bool(ok).is_false()
	assert_int(w.balance(COINS)).is_equal(100)                       # restored
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_not_null()
	var rb := _event_of(EconomyEvent.Kind.TRANSACTION_ROLLED_BACK)
	assert_object(rb).is_not_null()
	assert_int(rb.amount).is_equal(50)


func test_rollback_near_cap_restores_exactly_not_via_earn() -> void:
	# AC-W05b regression: snapshot restore must be exact, never an earn() the cap clamp
	# could truncate (or that daily-cap/compliance could block).
	var w = _make(995, 0, _config_with_coins_max(1000))
	var fail := func() -> bool: return false
	var ok: bool = w.spend(COINS, 250, fail)
	assert_bool(ok).is_false()
	assert_int(w.balance(COINS)).is_equal(995)   # exact, not 745-then-(re-earned/clamped)
	assert_int(_event_of(EconomyEvent.Kind.TRANSACTION_ROLLED_BACK).amount).is_equal(250)


func test_spend_with_successful_action_commits() -> void:
	var w = _make(100)
	var succeed := func() -> bool: return true
	var ok: bool = w.spend(COINS, 50, succeed)
	assert_bool(ok).is_true()
	assert_int(w.balance(COINS)).is_equal(50)
	assert_object(_event_of(EconomyEvent.Kind.TRANSACTION_ROLLED_BACK)).is_null()


# --- boundary / DI / gems ---

func test_all_coin_boosters_unaffordable_at_zero_balance() -> void:
	var w = _make(0)
	assert_bool(w.spend(COINS, 120)).is_false()   # Hint
	assert_bool(w.spend(COINS, 250)).is_false()   # Reshuffle
	assert_bool(w.spend(COINS, 350)).is_false()   # Extra Discard
	assert_int(w.balance(COINS)).is_equal(0)


func test_configure_di_operates_on_injected_stub_only() -> void:
	# Proves no autoload is required: the service spends + persists through the stub.
	var w = _make(200)
	assert_bool(w.spend(COINS, 50)).is_true()
	assert_int(_save_stub.data.wallet_coins).is_equal(150)
	assert_int(_save_stub.save_called).is_greater_equal(1)


func test_gems_earn_and_spend_use_gem_balance() -> void:
	var w = _make(0, 20)
	assert_int(w.earn(GEMS, 5, EconomyEnums.EarnSource.MILESTONE_GIFT)).is_equal(5)
	assert_int(w.balance(GEMS)).is_equal(25)
	assert_bool(w.spend(GEMS, 7)).is_true()
	assert_int(w.balance(GEMS)).is_equal(18)
	assert_int(w.balance(COINS)).is_equal(0)   # coins untouched


func test_reset_level_state_zeroes_all_fields() -> void:
	var w = _make(0)
	w.reshuffle_count = 3
	w.boosters_used_this_level = 2
	w.extra_discard_active = true
	w.reset_level_state()
	assert_int(w.reshuffle_count).is_equal(0)
	assert_int(w.boosters_used_this_level).is_equal(0)
	assert_bool(w.extra_discard_active).is_false()


func test_reset_level_state_accepts_level_arg_for_signal_binding() -> void:
	var w = _make(0)
	w.boosters_used_this_level = 5
	w.reset_level_state(42)   # bindable to level_started(level: int)
	assert_int(w.boosters_used_this_level).is_equal(0)


# ---------------------------------------------------------------------------
# Hint booster (S3-007): use_hint + notify_hint_consumed
# ---------------------------------------------------------------------------

## Builds a minimal fully-exposed BoardModel. All results are the same value and
## no stack in [param queue] targets that value, so every card goes to discard
## unless specified otherwise. The first [param exposed_count] cards have no
## coverers; all others are unreachable (covered by a card id outside the set).
func _open_board(results: Array[int], queue: Array[int]) -> BoardModel:
	var covered_by: Dictionary = {}
	for i in results.size():
		covered_by[i] = [] as Array[int]
	return BoardModel.new(results, covered_by, queue)


func test_use_hint_success_deducts_coins_returns_best_card_emits_events() -> void:
	## AC-H01: enough coins, board with 3 exposed cards (scores 220/35/200).
	## Expected: deducts 120, emits CURRENCY_SPENT + HINT_RESULT(card=2) + BOOSTER_ACTIVATED,
	## returns card_id 2, boosters_used_this_level == 1.
	#
	# Build the Formula 5 worked-example board (same as test_hint_score.gd):
	#   results: [99,99,7,99,99,9,99,9,7]
	#   queue:   [7,11,13,17]  (result-9 cards go to discard)
	#   card 0,1 covered by card 2; card 3,4,6 covered by card 5; card 7 fully exposed
	#   card 2 → score 220; card 5 → score 35; card 8 → score 200
	var covered_by: Dictionary = {
		0: [2] as Array[int], 1: [2] as Array[int], 2: [] as Array[int],
		3: [5] as Array[int], 4: [5] as Array[int], 5: [] as Array[int],
		6: [5] as Array[int], 7: [] as Array[int],  8: [] as Array[int],
	}
	var results: Array[int] = [99, 99, 7, 99, 99, 9, 99, 9, 7]
	var board := BoardModel.new(results, covered_by, [7, 11, 13, 17])
	# Discard card 7 (result 9 → discard, since no stack targets 9) → relief=1 for card 5.
	board.tap_card(7)

	var w = _make(200)  # 200 coins > 120 cost
	var card_id: int = w.use_hint(board)

	# Returns the best card.
	assert_int(card_id).is_equal(2)
	# Coins deducted.
	assert_int(w.balance(COINS)).is_equal(80)
	# boosters_used_this_level incremented.
	assert_int(w.boosters_used_this_level).is_equal(1)

	# Events: CURRENCY_SPENT then HINT_RESULT then BOOSTER_ACTIVATED.
	var kinds: Array = []
	for e: EconomyEvent in _events:
		kinds.append(e.kind)
	assert_bool(kinds.has(EconomyEvent.Kind.CURRENCY_SPENT)).is_true()
	assert_bool(kinds.has(EconomyEvent.Kind.HINT_RESULT)).is_true()
	assert_bool(kinds.has(EconomyEvent.Kind.BOOSTER_ACTIVATED)).is_true()

	# CURRENCY_SPENT comes before HINT_RESULT.
	var spent_idx: int = kinds.find(EconomyEvent.Kind.CURRENCY_SPENT)
	var hint_idx: int = kinds.find(EconomyEvent.Kind.HINT_RESULT)
	assert_bool(spent_idx < hint_idx).is_true()

	# HINT_RESULT carries only card_id (AC-M01a).
	var hint_evt: EconomyEvent = _event_of(EconomyEvent.Kind.HINT_RESULT)
	assert_int(hint_evt.card_id).is_equal(2)

	# BOOSTER_ACTIVATED carries the HINT booster type.
	var act_evt: EconomyEvent = _event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED)
	assert_int(act_evt.booster_type).is_equal(EconomyEnums.BoosterType.HINT)


func test_use_hint_ac_m01a_hint_result_has_only_card_id_set() -> void:
	## AC-M01a: HINT_RESULT payload contains only card_id; all other fields
	## remain at their sentinel defaults (-1 / 0). This is the no-arithmetic-
	## solving structural check — no result, operands, or solution_text.
	var board := _open_board([7], [7, 9, 11, 13])
	var w = _make(200)
	w.use_hint(board)

	var evt: EconomyEvent = _event_of(EconomyEvent.Kind.HINT_RESULT)
	assert_object(evt).is_not_null()
	assert_int(evt.card_id).is_equal(0)   # only card, so card 0 is selected
	# All other payload fields must be at sentinel defaults.
	assert_int(evt.currency).is_equal(-1)
	assert_int(evt.amount).is_equal(0)
	assert_int(evt.source).is_equal(-1)
	assert_int(evt.new_balance).is_equal(-1)
	assert_int(evt.booster_type).is_equal(-1)
	assert_int(evt.reason).is_equal(-1)
	assert_int(evt.sku).is_equal(-1)


func test_use_hint_ac_h03_no_exposed_cards_precondition_failed_no_spend() -> void:
	## AC-H03: board with 0 exposed cards → BOOSTER_PRECONDITION_FAILED, coins unchanged.
	# Mutual coverage → neither card is exposed.
	var covered_by: Dictionary = {
		0: [1] as Array[int],
		1: [0] as Array[int],
	}
	var board := BoardModel.new([7, 9], covered_by, [7, 9, 11, 13])
	var w = _make(500)
	var result: int = w.use_hint(board)

	assert_int(result).is_equal(-1)
	assert_int(w.balance(COINS)).is_equal(500)  # no deduction

	var evt: EconomyEvent = _event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)
	assert_object(evt).is_not_null()
	assert_int(evt.booster_type).is_equal(EconomyEnums.BoosterType.HINT)
	assert_int(evt.reason).is_equal(EconomyEnums.FailReason.NO_EXPOSED_CARD)
	# No CURRENCY_SPENT event.
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


func test_use_hint_ac_h04_double_tap_rejected_no_second_deduction() -> void:
	## AC-H04 / EC-08: while _hint_in_progress is true, a second use_hint call
	## is rejected with BOOSTER_PURCHASE_FAILED(ALREADY_IN_PROGRESS). No second
	## coin deduction. notify_hint_consumed() re-enables it.
	var board := _open_board([7], [7, 9, 11, 13])
	var w = _make(500)

	# First call succeeds.
	var first: int = w.use_hint(board)
	assert_int(first).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(380)  # 500 - 120

	# Second call while in-progress.
	_events = []
	var second: int = w.use_hint(board)
	assert_int(second).is_equal(-1)
	assert_int(w.balance(COINS)).is_equal(380)  # no further deduction

	var failed_evt: EconomyEvent = _event_of(EconomyEvent.Kind.BOOSTER_PURCHASE_FAILED)
	assert_object(failed_evt).is_not_null()
	assert_int(failed_evt.booster_type).is_equal(EconomyEnums.BoosterType.HINT)
	assert_int(failed_evt.reason).is_equal(EconomyEnums.FailReason.ALREADY_IN_PROGRESS)

	# After notify_hint_consumed(), another call succeeds again.
	w.notify_hint_consumed()
	_events = []
	var third: int = w.use_hint(board)
	assert_int(third).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(260)  # 380 - 120


func test_use_hint_insufficient_coins_returns_minus_one_not_in_progress() -> void:
	## Insufficient balance → SPEND_FAILED emitted, returns -1, _hint_in_progress stays false.
	var board := _open_board([7], [7, 9, 11, 13])
	var w = _make(0)  # 0 coins, Hint costs 120
	var result: int = w.use_hint(board)

	assert_int(result).is_equal(-1)
	assert_int(w.balance(COINS)).is_equal(0)

	var failed_evt: EconomyEvent = _event_of(EconomyEvent.Kind.SPEND_FAILED)
	assert_object(failed_evt).is_not_null()

	# _hint_in_progress must NOT be set to true on a failed spend (subsequent calls
	# should not be rejected with ALREADY_IN_PROGRESS).
	_events = []
	w.earn(COINS, 120, LEVEL_WIN)
	_events = []
	var retry: int = w.use_hint(board)
	assert_int(retry).is_equal(0)  # succeeds — not stuck in progress


func test_use_hint_boosters_used_incremented_on_success_only() -> void:
	## boosters_used_this_level increments on success; stays 0 on every failure path.
	var board := _open_board([7], [7, 9, 11, 13])

	# Insufficient coins — no increment.
	var w_broke = _make(0)
	w_broke.use_hint(board)
	assert_int(w_broke.boosters_used_this_level).is_equal(0)

	# No exposed cards — no increment.
	var covered_by: Dictionary = {0: [1] as Array[int], 1: [0] as Array[int]}
	var empty_board := BoardModel.new([7, 9], covered_by, [7, 9, 11, 13])
	var w_empty = _make(500)
	w_empty.use_hint(empty_board)
	assert_int(w_empty.boosters_used_this_level).is_equal(0)

	# Successful activation — increment to 1.
	var w_ok = _make(500)
	w_ok.use_hint(board)
	assert_int(w_ok.boosters_used_this_level).is_equal(1)
