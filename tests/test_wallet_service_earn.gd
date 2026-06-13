extends GdUnitTestSuite
## Tests for WalletService.grant_level_win — the level-win earn triggers (S3-008).
##
## Covers Formula 1 (star-weighted base + once-per-day first-win bonus) and
## Formula 1b (clean-clear efficiency bonus), plus the daily-win persistence that
## makes the first-win bonus survive an app restart within the same UTC day.
##
## WalletService is instantiated directly (NOT via the autoload) and configured
## with injected stubs (fake save, FixedTimeProvider, permissive compliance,
## default EconomyConfig) so every test is isolated and deterministic.
## Source: design/gdd/deck-economy.md Formula 1/1b; AC-EF01/EF02, AC-EFF01-03.

const WALLET := preload("res://autoloads/wallet_service.gd")

const COINS := EconomyEnums.Currency.COINS
const LEVEL_WIN := EconomyEnums.EarnSource.LEVEL_WIN


# Minimal SaveService stand-in: real SaveData, a counted save_game(), no file I/O.
class StubSave extends RefCounted:
	var data: SaveData
	var save_called: int = 0
	func _init() -> void:
		data = SaveData.new()
	func save_game() -> void:
		save_called += 1


class StubCompliance extends RefCounted:
	var restricted: bool = false
	func is_restricted() -> bool:
		return restricted


var _events: Array = []
var _save_stub: StubSave
var _time_stub: FixedTimeProvider


## Builds a configured WalletService. [param config] / [param time_stub] are optional
## overrides; defaults are a fresh EconomyConfig and a FixedTimeProvider at epoch 0.
func _make(config: EconomyConfig = null, time_stub: FixedTimeProvider = null):
	_events = []
	_save_stub = StubSave.new()
	var cfg: EconomyConfig = config if config != null else EconomyConfig.new()
	_time_stub = time_stub if time_stub != null else FixedTimeProvider.new()
	var svc = auto_free(WALLET.new())
	svc.configure(_save_stub, StubCompliance.new(), _time_stub, cfg)
	svc.economy_event.connect(func(e: EconomyEvent) -> void: _events.append(e))
	return svc


func _earned() -> EconomyEvent:
	for e in _events:
		if e.kind == EconomyEvent.Kind.CURRENCY_EARNED:
			return e
	return null


# --- star-weighted base + flat fallback (Formula 1) ---

func test_grant_level_win_2_star_first_clean_grants_base_first_and_clean() -> void:
	# AC-EFF01 / AC-EF: first win of the day, 2 stars, no boosters → 55 + 15 + 20 = 90.
	var w = _make()
	var credited: int = w.grant_level_win(2)
	assert_int(credited).is_equal(90)
	assert_int(w.balance(COINS)).is_equal(90)
	var e := _earned()
	assert_int(e.source).is_equal(LEVEL_WIN)
	assert_int(e.amount).is_equal(90)   # single summed CURRENCY_EARNED


func test_grant_level_win_3_star_first_clean_worked_example_is_110() -> void:
	# AC-EF01: first_win_today, 3-star clean clear → 75 + 15 + 20 = 110.
	var w = _make()
	assert_int(w.grant_level_win(3)).is_equal(110)


func test_grant_level_win_unknown_stars_uses_flat_fallback() -> void:
	# stars == 0 (no scoring yet, S2-011 deferred) → coins_win_flat_fallback (50).
	# First clean win adds 15 + 20 → 85.
	var w = _make()
	assert_int(w.grant_level_win(0)).is_equal(50 + 15 + 20)


func test_grant_level_win_1_star_uses_one_star_value() -> void:
	var w = _make()
	# 1-star clean first win → 40 + 15 + 20 = 75.
	assert_int(w.grant_level_win(1)).is_equal(75)


# --- first-win bonus once per day (AC-EF02) ---

func test_second_win_same_day_omits_first_win_bonus() -> void:
	# AC-EF02: first win applies first_win_bonus (15), the second on the same day applies 0.
	var w = _make()
	assert_int(w.grant_level_win(2)).is_equal(55 + 15 + 20)   # first: 90
	_events = []
	assert_int(w.grant_level_win(2)).is_equal(55 + 20)        # second: 75 (no first-win bonus)


func test_first_win_bonus_persists_across_restart_same_day() -> void:
	# wins_today is persisted, so a fresh WalletService over the same save does NOT
	# re-grant the first-win bonus within the same UTC day.
	var w = _make()
	w.grant_level_win(2)                                   # consumes the first-win bonus
	assert_int(_save_stub.data.wins_today).is_equal(1)
	# "Restart": new service instance, same save + clock.
	var w2 = auto_free(WALLET.new())
	w2.configure(_save_stub, StubCompliance.new(), _time_stub, EconomyConfig.new())
	assert_int(w2.grant_level_win(2)).is_equal(55 + 20)    # no first-win bonus again


func test_day_rollover_re_enables_first_win_bonus() -> void:
	# After the UTC day advances, wins_today resets and the first-win bonus applies again.
	var clock := FixedTimeProvider.new()
	clock.now_seconds = 0
	var w = _make(null, clock)
	assert_int(w.grant_level_win(2)).is_equal(90)          # day 0 first win: +15 +20
	_events = []
	clock.now_seconds = 86_400                             # advance one UTC day
	assert_int(w.grant_level_win(2)).is_equal(90)          # day 1 first win: +15 +20 again


# --- clean-clear bonus (Formula 1b / AC-EFF02-03) ---

func test_clean_clear_bonus_forfeited_when_a_booster_was_used() -> void:
	# AC-EFF02: boosters_used_this_level >= 1 → no clean-clear bonus.
	# Use a non-first win to isolate the clean bonus (pre-set wins_today).
	var w = _make()
	_save_stub.data.wins_today = 1            # not the first win today
	w.boosters_used_this_level = 1            # a booster was activated this level
	assert_int(w.grant_level_win(2)).is_equal(55)   # base only, no clean bonus


func test_clean_clear_bonus_applied_when_no_booster_used() -> void:
	# Sibling of the above to isolate the bonus: same setup, zero boosters → +20.
	var w = _make()
	_save_stub.data.wins_today = 1            # not the first win today
	w.boosters_used_this_level = 0
	assert_int(w.grant_level_win(2)).is_equal(55 + 20)


func test_clean_clear_bonus_knob_disabled_adds_nothing() -> void:
	# AC-EFF03: clean_clear_bonus == 0 → no bonus even on a clean clear.
	var cfg := EconomyConfig.new()
	cfg.clean_clear_bonus = 0
	var w = _make(cfg)
	_save_stub.data.wins_today = 1            # isolate from the first-win bonus
	assert_int(w.grant_level_win(2)).is_equal(55)


# --- persistence + live signal handler ---

func test_grant_level_win_persists_balance_and_win_counter() -> void:
	var w = _make()
	w.grant_level_win(2)
	assert_int(_save_stub.data.wallet_coins).is_equal(90)
	assert_int(_save_stub.data.wins_today).is_equal(1)
	assert_int(_save_stub.save_called).is_greater_equal(1)


func test_on_level_completed_handler_grants_flat_fallback() -> void:
	# The live GameManager.level_completed wiring grants the flat-fallback reward
	# (stars unavailable until S2-011). Handler accepts the level argument.
	var w = _make()
	w._on_level_completed(7)
	assert_int(w.balance(COINS)).is_equal(50 + 15 + 20)   # flat fallback, first clean win
	assert_int(_earned().source).is_equal(LEVEL_WIN)
