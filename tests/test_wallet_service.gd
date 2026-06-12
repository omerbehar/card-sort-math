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
