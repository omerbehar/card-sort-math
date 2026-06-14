extends GdUnitTestSuite
## Tests for the WalletService transaction core (S3-004 / S3-005).
##
## WalletService is instantiated directly (NOT via the autoload) and configured with
## injected stubs — a fake save, a FixedTimeProvider, a compliance stub, and an
## EconomyConfig — so every test is isolated and proves the logic has no autoload
## coupling (DI over singletons). Emitted [EconomyEvent]s are captured for assertion.

const WALLET := preload("res://autoloads/wallet_service.gd")

const COINS := EconomyEnums.Currency.COINS
const GEMS := EconomyEnums.Currency.GEMS
const LEVEL_WIN := EconomyEnums.EarnSource.LEVEL_WIN
const REWARDED_AD := EconomyEnums.EarnSource.REWARDED_AD
const GEM_CONVERT := EconomyEnums.EarnSource.GEM_CONVERT

# A minimal stand-in for SaveService: real SaveData, a counted save_game(), no file I/O.
class StubSave extends RefCounted:
	var data: SaveData
	var save_called: int = 0
	func _init() -> void:
		data = SaveData.new()
	func save_game() -> void:
		save_called += 1


## Compliance stub. Set [member restricted] before injecting into a WalletService.
## Implements only the is_restricted() surface the economy consults (AC-CL02/CL03).
class StubCompliance extends RefCounted:
	var restricted: bool = false
	func is_restricted() -> bool:
		return restricted


var _events: Array = []
var _save_stub: StubSave
var _time_stub: FixedTimeProvider


## Builds a configured WalletService seeded to the given balances.
## [param coins] / [param gems]: starting balances.
## [param config]: optional EconomyConfig override (e.g. small coins_max for cap tests).
## [param compliance]: optional StubCompliance; defaults to a permissive stub (not restricted).
## [param time_stub]: optional FixedTimeProvider; defaults to a new one at epoch 0.
## All S3-004 tests pass null/default compliance so they are unaffected by the new arg.
func _make(
		coins: int = 0,
		gems: int = 0,
		config: EconomyConfig = null,
		compliance: StubCompliance = null,
		time_stub: FixedTimeProvider = null):
	_events = []
	_save_stub = StubSave.new()
	_save_stub.data.wallet_coins = coins
	_save_stub.data.wallet_gems = gems
	var cfg: EconomyConfig = config if config != null else EconomyConfig.new()
	var comp: StubCompliance = compliance if compliance != null else StubCompliance.new()
	_time_stub = time_stub if time_stub != null else FixedTimeProvider.new()
	var svc = auto_free(WALLET.new())
	svc.configure(_save_stub, comp, _time_stub, cfg)
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
# Picker booster (replaces Hint): use_picker plays a chosen COVERED card
# ---------------------------------------------------------------------------

const PICKER := EconomyEnums.BoosterType.PICKER


func test_use_picker_plays_a_covered_card_and_deducts() -> void:
	# Card 1 (result 7) is covered by card 0, so it is NOT normally tappable. The
	# Picker plays it anyway: it routes to the open "7" stack. 120 coins deducted.
	var covered_by: Dictionary = {0: [] as Array[int], 1: [0] as Array[int]}
	var board := BoardModel.new([5, 7], covered_by, [7, 9, 11, 13])
	assert_bool(board.is_exposed(1)).is_false()   # precondition: card 1 is covered

	var w = _make(200)
	var events: Array = w.use_picker(board, 1)

	assert_bool(events.is_empty()).is_false()      # the pick produced board events
	assert_bool(board.is_card_removed(1)).is_true() # the covered card was played
	assert_int(w.balance(COINS)).is_equal(80)       # 200 - 120
	assert_int(w.boosters_used_this_level).is_equal(1)
	var act := _event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED)
	assert_object(act).is_not_null()
	assert_int(act.booster_type).is_equal(PICKER)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_not_null()


func test_use_picker_insufficient_coins_returns_empty_no_play() -> void:
	var covered_by: Dictionary = {0: [] as Array[int], 1: [0] as Array[int]}
	var board := BoardModel.new([5, 7], covered_by, [7, 9, 11, 13])
	var w = _make(0)                                # Picker costs 120
	var events: Array = w.use_picker(board, 1)
	assert_bool(events.is_empty()).is_true()
	assert_bool(board.is_card_removed(1)).is_false()
	assert_int(w.boosters_used_this_level).is_equal(0)
	assert_object(_event_of(EconomyEvent.Kind.SPEND_FAILED)).is_not_null()


func test_use_picker_invalid_target_already_removed_blocked_no_spend() -> void:
	var covered_by: Dictionary = {0: [] as Array[int], 1: [] as Array[int]}
	var board := BoardModel.new([99, 99], covered_by, [1, 2, 3, 4])
	board.tap_card(0)                               # card 0 now removed (discarded)
	var w = _make(500)
	var events: Array = w.use_picker(board, 0)      # target a gone card
	assert_bool(events.is_empty()).is_true()
	assert_int(w.balance(COINS)).is_equal(500)      # no deduction
	var pf := _event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)
	assert_object(pf).is_not_null()
	assert_int(pf.booster_type).is_equal(PICKER)
	assert_int(pf.reason).is_equal(EconomyEnums.FailReason.INVALID_TARGET)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


# ---------------------------------------------------------------------------
# Reshuffle booster (S3-009): use_reshuffle
# ---------------------------------------------------------------------------

const RESHUFFLE := EconomyEnums.BoosterType.RESHUFFLE


## Flat (all-exposed, non-overlapping) placements for [param n] cards.
func _flat_placements(n: int) -> Array:
	var p: Array = []
	for i in n:
		p.append({pos = Vector2(i * 100.0, 0.0), layer = 0})
	return p


## A fresh, non-won board of [param n] flat cards (results 1..n, queue 1..n).
func _flat_board(n: int) -> BoardModel:
	var results: Array[int] = []
	var covered_by: Dictionary = {}
	var queue: Array[int] = []
	for i in n:
		results.append(i + 1)
		covered_by[i] = [] as Array[int]
		queue.append(i + 1)
	return BoardModel.new(results, covered_by, queue)


func test_use_reshuffle_success_deducts_and_increments_count() -> void:
	var board := _flat_board(6)
	var w = _make(300)
	w.reset_level_state(42)                          # captures level id + clock
	var assignment: Array = w.use_reshuffle(board, _flat_placements(6))
	assert_bool(assignment.is_empty()).is_false()    # returns the new layout
	assert_int(w.balance(COINS)).is_equal(50)        # 300 - 250
	assert_int(w.reshuffle_count).is_equal(1)
	assert_int(w.boosters_used_this_level).is_equal(1)
	var act := _event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED)
	assert_object(act).is_not_null()
	assert_int(act.booster_type).is_equal(RESHUFFLE)


func test_use_reshuffle_on_won_board_blocked_no_spend() -> void:
	# AC-R05 / EC-15: a won board blocks Reshuffle with WON_BOARD, coins unchanged.
	var board := _flat_board(4)
	for i in 4:
		board.tap_card(i)                            # route all → floor empty → WIN
	assert_bool(board.is_won()).is_true()
	var w = _make(500)
	w.reset_level_state(1)
	var assignment: Array = w.use_reshuffle(board, _flat_placements(4))
	assert_bool(assignment.is_empty()).is_true()
	assert_int(w.balance(COINS)).is_equal(500)       # no deduction
	var pf := _event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)
	assert_object(pf).is_not_null()
	assert_int(pf.booster_type).is_equal(RESHUFFLE)
	assert_int(pf.reason).is_equal(EconomyEnums.FailReason.WON_BOARD)
	assert_int(w.reshuffle_count).is_equal(0)


func test_use_reshuffle_insufficient_coins_returns_false() -> void:
	var board := _flat_board(6)
	var w = _make(0)                                 # Reshuffle costs 250
	w.reset_level_state(1)
	assert_bool(w.use_reshuffle(board, _flat_placements(6)).is_empty()).is_true()
	assert_int(w.reshuffle_count).is_equal(0)
	assert_int(w.boosters_used_this_level).is_equal(0)
	assert_object(_event_of(EconomyEvent.Kind.SPEND_FAILED)).is_not_null()


# ============================================================================
# S3-005 — compliance gating, daily caps, gem→coin conversion
# ============================================================================

func _restricted() -> StubCompliance:
	var c := StubCompliance.new()
	c.restricted = true
	return c


func test_rewarded_ad_at_coin_cap_credits_nothing_and_emits_cap_reached() -> void:
	# AC-C01: ad coins already at daily_coins_cap (500) -> earn credits 0, cap event.
	var w = _make(1000)
	_save_stub.data.ad_coins_today = 500                 # default daily_coins_cap
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(1000)
	var cap := _event_of(EconomyEvent.Kind.EARN_CAP_REACHED)
	assert_object(cap).is_not_null()
	assert_int(cap.source).is_equal(REWARDED_AD)
	assert_int(cap.reason).is_equal(EconomyEnums.FailReason.DAILY_COIN_CAP)


func test_rewarded_ad_partial_cap_credits_remaining_only() -> void:
	# AC-C02 / EC-11: 460 of 500 used -> a 60-coin ad credits only 40.
	var w = _make(0)
	_save_stub.data.ad_coins_today = 460
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(40)
	assert_int(w.balance(COINS)).is_equal(40)
	var e := _event_of(EconomyEvent.Kind.CURRENCY_EARNED)
	assert_int(e.amount).is_equal(40)
	assert_int(e.source).is_equal(REWARDED_AD)


func test_level_win_uncapped_even_at_ad_cap() -> void:
	# AC-C03: daily_coins_cap is REWARDED_AD-only; LEVEL_WIN ignores it.
	var w = _make(0)
	_save_stub.data.ad_coins_today = 500
	assert_int(w.earn(COINS, 55, LEVEL_WIN)).is_equal(55)
	assert_int(w.balance(COINS)).is_equal(55)


func test_child_level_win_earn_succeeds_play_earn_ungated() -> void:
	# AC-CH01: restricted user still earns from play.
	var w = _make(0, 0, null, _restricted())
	assert_int(w.earn(COINS, 55, LEVEL_WIN)).is_equal(55)
	assert_int(w.balance(COINS)).is_equal(55)


func test_child_rewarded_ad_earn_blocked() -> void:
	# AC-CH02 / AC-CL02: restricted user's ad earn is blocked (gate routes via is_restricted()).
	var w = _make(0, 0, null, _restricted())
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(0)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_EARNED)).is_null()


func test_restricted_iap_blocked_emits_iap_blocked() -> void:
	# AC-CL01: restricted -> initiate_iap false, IAP_BLOCKED, gems unchanged.
	var w = _make(0, 100, null, _restricted())
	assert_bool(w.initiate_iap(3)).is_false()
	assert_int(w.balance(GEMS)).is_equal(100)
	var e := _event_of(EconomyEvent.Kind.IAP_BLOCKED)
	assert_object(e).is_not_null()
	assert_int(e.sku).is_equal(3)
	assert_int(e.reason).is_equal(EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)


func test_unrestricted_iap_proceeds_without_block_event() -> void:
	var w = _make(0, 100)                                # default permissive compliance
	assert_bool(w.initiate_iap(3)).is_true()
	assert_object(_event_of(EconomyEvent.Kind.IAP_BLOCKED)).is_null()


func test_convert_gems_to_coins_spends_gems_credits_coins() -> void:
	# AC-GC01: 10 gems -> 250 coins; both spend + earn events.
	var w = _make(100, 20)
	assert_bool(w.convert_gems_to_coins(10)).is_true()
	assert_int(w.balance(GEMS)).is_equal(10)
	assert_int(w.balance(COINS)).is_equal(350)
	var spent := _event_of(EconomyEvent.Kind.CURRENCY_SPENT)
	assert_int(spent.currency).is_equal(GEMS)
	assert_int(spent.amount).is_equal(10)
	assert_int(spent.new_balance).is_equal(10)
	var earned := _event_of(EconomyEvent.Kind.CURRENCY_EARNED)
	assert_int(earned.currency).is_equal(COINS)
	assert_int(earned.amount).is_equal(250)
	assert_int(earned.source).is_equal(GEM_CONVERT)
	assert_int(earned.new_balance).is_equal(350)


func test_convert_gems_at_daily_cap_blocked() -> void:
	# AC-GC02 / EC-13: 50 gems already converted today -> next conversion blocked.
	var w = _make(0, 20)
	_save_stub.data.gems_converted_today = 50           # default daily_gem_convert_cap
	assert_bool(w.convert_gems_to_coins(1)).is_false()
	assert_int(w.balance(GEMS)).is_equal(20)
	var cap := _event_of(EconomyEvent.Kind.EARN_CAP_REACHED)
	assert_int(cap.source).is_equal(GEM_CONVERT)
	assert_int(cap.reason).is_equal(EconomyEnums.FailReason.GEM_CONVERT_CAP)


func test_convert_gems_insufficient_balance_fails() -> void:
	# AC-GC03: not enough gems -> SPEND_FAILED, no change.
	var w = _make(0, 5)
	assert_bool(w.convert_gems_to_coins(10)).is_false()
	assert_int(w.balance(GEMS)).is_equal(5)
	var sf := _event_of(EconomyEvent.Kind.SPEND_FAILED)
	assert_int(sf.currency).is_equal(GEMS)
	assert_int(sf.amount).is_equal(10)


func test_convert_gems_zero_amount_guarded() -> void:
	# EC-14: 0-amount conversion is a no-op with no event.
	var w = _make(0, 20)
	assert_bool(w.convert_gems_to_coins(0)).is_false()
	assert_int(w.balance(GEMS)).is_equal(20)
	assert_int(_events.size()).is_equal(0)


func test_daily_counters_reset_on_day_rollover() -> void:
	# Caps reset when utc_day_key() advances (TimeProvider-driven).
	var clock := FixedTimeProvider.new()
	clock.now_seconds = 0
	var w = _make(0, 0, null, null, clock)
	_save_stub.data.ad_coins_today = 500                # at cap on day 0
	assert_bool(w.is_ad_earn_available()).is_false()
	clock.now_seconds = 86_400                          # advance one UTC day
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(60)   # counters rolled -> succeeds
	assert_int(w.balance(COINS)).is_equal(60)


func test_rewarded_ad_count_cap_blocks_after_max_ads() -> void:
	# Formula 8: after max_ads_per_day (3) earns, the next is capped (coin cap not yet hit).
	var w = _make(0)
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(60)
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(60)
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(60)
	assert_int(w.balance(COINS)).is_equal(180)
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(0)    # 4th -> count cap
	assert_int(w.balance(COINS)).is_equal(180)
	var cap := _event_of(EconomyEvent.Kind.EARN_CAP_REACHED)
	assert_int(cap.source).is_equal(REWARDED_AD)
	assert_int(cap.reason).is_equal(EconomyEnums.FailReason.AD_COUNT_CAP)


func test_is_ad_earn_available_reflects_compliance_and_caps() -> void:
	assert_bool(_make(0).is_ad_earn_available()).is_true()           # fresh + permissive
	assert_bool(_make(0, 0, null, _restricted()).is_ad_earn_available()).is_false()  # restricted
	var w = _make(0)
	_save_stub.data.ad_coins_today = 500
	assert_bool(w.is_ad_earn_available()).is_false()                 # at coin cap


# ---------------------------------------------------------------------------
# Wallet hard-cap (coins_max) interaction — value-loss guards (review S2 / N2)
# ---------------------------------------------------------------------------

func test_rewarded_ad_with_full_wallet_emits_wallet_full_and_consumes_no_ad() -> void:
	# Wallet already at coins_max but daily ad headroom remains: the credit clamps to 0.
	# The ad view must NOT be consumed and a WALLET_FULL cap event must surface
	# (regression: previously incremented ads_watched_today for a 0-coin payout).
	var w = _make(1000, 0, _config_with_coins_max(1000))   # at coin hard cap, day counters 0
	assert_int(w.earn(COINS, 60, REWARDED_AD)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(1000)
	# Ad counters untouched — no ad was "spent".
	assert_int(_save_stub.data.ads_watched_today).is_equal(0)
	assert_int(_save_stub.data.ad_coins_today).is_equal(0)
	var cap := _event_of(EconomyEvent.Kind.EARN_CAP_REACHED)
	assert_object(cap).is_not_null()
	assert_int(cap.source).is_equal(REWARDED_AD)
	assert_int(cap.reason).is_equal(EconomyEnums.FailReason.WALLET_FULL)
	# No spurious credit event.
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_EARNED)).is_null()


func test_convert_gems_aborts_without_spending_when_coin_wallet_full() -> void:
	# AC-W05b sibling: the coin payout would exceed coins_max, so the conversion must
	# abort BEFORE spending gems — gems are never burned for a truncated payout.
	var cfg := _config_with_coins_max(1000)   # gem_to_coin_rate default 25
	var w = _make(990, 20, cfg)               # 10 gems -> 250 coins, but only 10 headroom
	assert_bool(w.convert_gems_to_coins(10)).is_false()
	assert_int(w.balance(GEMS)).is_equal(20)  # gems preserved
	assert_int(w.balance(COINS)).is_equal(990)
	assert_int(_save_stub.data.gems_converted_today).is_equal(0)
	var cap := _event_of(EconomyEvent.Kind.EARN_CAP_REACHED)
	assert_object(cap).is_not_null()
	assert_int(cap.source).is_equal(GEM_CONVERT)
	assert_int(cap.reason).is_equal(EconomyEnums.FailReason.WALLET_FULL)
	# No gem spend occurred.
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


func test_convert_gems_exact_fit_at_coin_cap_succeeds() -> void:
	# Boundary: the payout that fills coins_max exactly must still succeed.
	var cfg := _config_with_coins_max(1000)   # 10 gems * 25 = 250 coins; 750 + 250 = 1000
	var w = _make(750, 20, cfg)
	assert_bool(w.convert_gems_to_coins(10)).is_true()
	assert_int(w.balance(COINS)).is_equal(1000)
	assert_int(w.balance(GEMS)).is_equal(10)


# ============================================================================
# S3-006 — Extra Discard Slot booster (use_extra_discard + ADR-0010 BoardModel)
# ============================================================================

const EXTRA_DISCARD := EconomyEnums.BoosterType.EXTRA_DISCARD


## Builds a fully-exposed board whose cards all discard (no stack targets their result).
func _discard_board(card_count: int) -> BoardModel:
	var results: Array[int] = []
	var covered_by: Dictionary = {}
	for i in card_count:
		results.append(99)
		covered_by[i] = [] as Array[int]
	return BoardModel.new(results, covered_by, [1, 2, 3, 4])


func test_use_extra_discard_with_room_expands_and_deducts() -> void:
	# AC-E01 / AC-E06: room remains (3 of 5 occupied) → 5→6, _discard.size()==6, 350 deducted.
	var board := _discard_board(4)
	board.tap_card(0)
	board.tap_card(1)
	board.tap_card(2)                       # 3 of 5 occupied — room remains
	var w = _make(500)
	var ok: bool = w.use_extra_discard(board)
	assert_bool(ok).is_true()
	assert_int(board.active_discard_slots()).is_equal(6)
	assert_int(board.discard_card(5)).is_equal(-1)         # new empty slot
	assert_int(w.balance(COINS)).is_equal(150)             # 500 - 350
	assert_bool(w.extra_discard_active).is_true()
	assert_int(w.boosters_used_this_level).is_equal(1)
	var act := _event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED)
	assert_object(act).is_not_null()
	assert_int(act.booster_type).is_equal(EXTRA_DISCARD)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_not_null()


func test_use_extra_discard_at_max_blocked_no_spend() -> void:
	# AC-E04 / EC-07: already at MAX_DISCARD_SLOTS (7) → AT_MAX, coins unchanged, no expand.
	var board := _discard_board(1)
	board.expand_discard()
	board.expand_discard()                  # 5 → 7 (at default max)
	var w = _make(500)
	var ok: bool = w.use_extra_discard(board)
	assert_bool(ok).is_false()
	assert_int(board.active_discard_slots()).is_equal(7)   # unchanged
	assert_int(w.balance(COINS)).is_equal(500)             # no deduction
	var pf := _event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)
	assert_object(pf).is_not_null()
	assert_int(pf.booster_type).is_equal(EXTRA_DISCARD)
	assert_int(pf.reason).is_equal(EconomyEnums.FailReason.AT_MAX)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


func test_use_extra_discard_when_row_full_now_expands_and_deducts() -> void:
	# Updated rule (ADR-0010, 2026-06-14): the row may be full — adding a slot at
	# 5/5 is the booster's whole point (rescue). It expands 5→6 and deducts; the old
	# "purchase-ahead-only / DISCARD_FULL block" was removed. Only the cap still gates.
	# 6 cards: fill all 5 slots, the 6th stays on the floor (no win).
	var board := _discard_board(6)
	for i in 5:
		board.tap_card(i)                   # slots 0..4 full (5/5)
	assert_int(board.occupied_discard_count()).is_equal(5)
	var w = _make(500)
	var ok: bool = w.use_extra_discard(board)
	assert_bool(ok).is_true()
	assert_int(board.active_discard_slots()).is_equal(6)   # slot added even when full
	assert_int(board.discard_card(5)).is_equal(-1)         # new empty slot
	assert_int(w.balance(COINS)).is_equal(150)             # 500 - 350
	assert_bool(w.extra_discard_active).is_true()
	assert_object(_event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED)).is_not_null()
	# No DISCARD_FULL precondition failure is emitted anymore.
	assert_object(_event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)).is_null()


func test_use_extra_discard_insufficient_coins_returns_false() -> void:
	# Not enough coins → SPEND_FAILED, false, no expansion, not active.
	var board := _discard_board(2)
	var w = _make(0)                        # Extra Discard costs 350
	assert_bool(w.use_extra_discard(board)).is_false()
	assert_int(board.active_discard_slots()).is_equal(5)
	assert_bool(w.extra_discard_active).is_false()
	assert_int(w.boosters_used_this_level).is_equal(0)
	assert_object(_event_of(EconomyEvent.Kind.SPEND_FAILED)).is_not_null()


func test_use_extra_discard_precondition_failure_does_not_increment_boosters() -> void:
	# A blocked activation (at max) must not increment boosters_used_this_level.
	var board := _discard_board(1)
	board.expand_discard()
	board.expand_discard()                  # at max 7
	var w = _make(500)
	w.use_extra_discard(board)
	assert_int(w.boosters_used_this_level).is_equal(0)
	assert_bool(w.extra_discard_active).is_false()


# ============================================================================
# Booster inventory (prototype owned counts) + *_from_stock activation paths
# ============================================================================

func _config_with_start(count: int) -> EconomyConfig:
	var cfg := EconomyConfig.new()
	cfg.starting_booster_count = count
	return cfg


func test_booster_count_seeded_from_config() -> void:
	var w = _make(0, 0, _config_with_start(3))
	assert_int(w.booster_count(PICKER)).is_equal(3)
	assert_int(w.booster_count(RESHUFFLE)).is_equal(3)
	assert_int(w.booster_count(EXTRA_DISCARD)).is_equal(3)
	assert_bool(_save_stub.data.boosters_seeded).is_true()   # seed gate set


func test_booster_counts_persist_in_savedata_and_survive_reload() -> void:
	# Counts live in SaveData and are restored on a fresh WalletService over the same save.
	var w = _make(0, 0, _config_with_start(3))
	w.consume_booster(PICKER)
	w.grant_booster(RESHUFFLE, 2)
	assert_int(_save_stub.data.boosters_picker).is_equal(2)
	assert_int(_save_stub.data.boosters_reshuffle).is_equal(5)

	var w2 = auto_free(WALLET.new())
	w2.configure(_save_stub, StubCompliance.new(), FixedTimeProvider.new(), _config_with_start(3))
	assert_int(w2.booster_count(PICKER)).is_equal(2)         # not re-seeded
	assert_int(w2.booster_count(RESHUFFLE)).is_equal(5)


func test_seed_does_not_re_grant_after_spending_to_zero() -> void:
	# An already-seeded save with 0 stock must NOT be topped back up on reload.
	var w = _make(0, 0, _config_with_start(1))
	w.consume_booster(PICKER)                                # picker now 0, seeded=true
	assert_int(w.booster_count(PICKER)).is_equal(0)
	var w2 = auto_free(WALLET.new())
	w2.configure(_save_stub, StubCompliance.new(), FixedTimeProvider.new(), _config_with_start(1))
	assert_int(w2.booster_count(PICKER)).is_equal(0)         # stays 0, not re-seeded to 1


func test_consume_booster_decrements_and_returns_true() -> void:
	var w = _make(0, 0, _config_with_start(2))
	assert_bool(w.consume_booster(PICKER)).is_true()
	assert_int(w.booster_count(PICKER)).is_equal(1)


func test_consume_booster_at_zero_returns_false_no_underflow() -> void:
	var w = _make(0, 0, _config_with_start(0))
	assert_bool(w.consume_booster(PICKER)).is_false()
	assert_int(w.booster_count(PICKER)).is_equal(0)


func test_grant_booster_increments_and_emits_stock_changed() -> void:
	var w = _make(0, 0, _config_with_start(0))
	var seen: Array = []
	w.booster_stock_changed.connect(func(t: int, n: int) -> void: seen.append([t, n]))
	w.grant_booster(PICKER, 1)
	assert_int(w.booster_count(PICKER)).is_equal(1)
	assert_int(seen.size()).is_equal(1)
	assert_int(seen[0][0]).is_equal(PICKER)
	assert_int(seen[0][1]).is_equal(1)


func test_use_picker_from_stock_consumes_count_and_does_not_spend_coins() -> void:
	var covered_by: Dictionary = {0: [] as Array[int], 1: [0] as Array[int]}
	var board := BoardModel.new([5, 7], covered_by, [7, 9, 11, 13])
	var w = _make(500, 0, _config_with_start(1))
	var events: Array = w.use_picker_from_stock(board, 1)
	assert_bool(events.is_empty()).is_false()           # the pick produced board events
	assert_bool(board.is_card_removed(1)).is_true()     # covered card played
	assert_int(w.booster_count(PICKER)).is_equal(0)     # consumed one
	assert_int(w.balance(COINS)).is_equal(500)          # NO coin spend
	assert_int(w.boosters_used_this_level).is_equal(1)
	assert_int(_event_of(EconomyEvent.Kind.BOOSTER_ACTIVATED).booster_type).is_equal(PICKER)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


func test_use_picker_from_stock_with_no_stock_blocked_no_play() -> void:
	var covered_by: Dictionary = {0: [] as Array[int], 1: [0] as Array[int]}
	var board := BoardModel.new([5, 7], covered_by, [7, 9, 11, 13])
	var w = _make(500, 0, _config_with_start(0))        # none owned
	var events: Array = w.use_picker_from_stock(board, 1)
	assert_bool(events.is_empty()).is_true()
	assert_bool(board.is_card_removed(1)).is_false()
	assert_int(w.balance(COINS)).is_equal(500)          # no spend
	var pf := _event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)
	assert_int(pf.booster_type).is_equal(PICKER)
	assert_int(pf.reason).is_equal(EconomyEnums.FailReason.NO_STOCK)


func test_use_reshuffle_from_stock_consumes_count_and_does_not_spend_coins() -> void:
	var board := _flat_board(6)
	var w = _make(500, 0, _config_with_start(1))
	w.reset_level_state(42)
	var assignment: Array = w.use_reshuffle_from_stock(board, _flat_placements(6))
	assert_bool(assignment.is_empty()).is_false()
	assert_int(w.booster_count(RESHUFFLE)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(500)          # NO coin spend
	assert_int(w.reshuffle_count).is_equal(1)
	assert_object(_event_of(EconomyEvent.Kind.CURRENCY_SPENT)).is_null()


func test_use_reshuffle_from_stock_with_no_stock_blocked() -> void:
	var board := _flat_board(6)
	var w = _make(500, 0, _config_with_start(0))
	w.reset_level_state(1)
	assert_bool(w.use_reshuffle_from_stock(board, _flat_placements(6)).is_empty()).is_true()
	assert_int(w.reshuffle_count).is_equal(0)
	assert_int(_event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED).reason) \
		.is_equal(EconomyEnums.FailReason.NO_STOCK)


func test_use_extra_discard_from_stock_consumes_count_and_does_not_spend_coins() -> void:
	var board := _discard_board(4)
	board.tap_card(0)
	board.tap_card(1)
	board.tap_card(2)                                   # room remains (3 of 5)
	var w = _make(500, 0, _config_with_start(1))
	assert_bool(w.use_extra_discard_from_stock(board)).is_true()
	assert_int(board.active_discard_slots()).is_equal(6)
	assert_int(w.booster_count(EXTRA_DISCARD)).is_equal(0)
	assert_int(w.balance(COINS)).is_equal(500)          # NO coin spend
	assert_bool(w.extra_discard_active).is_true()


func test_use_extra_discard_from_stock_with_no_stock_blocked() -> void:
	var board := _discard_board(4)
	var w = _make(500, 0, _config_with_start(0))
	assert_bool(w.use_extra_discard_from_stock(board)).is_false()
	assert_int(board.active_discard_slots()).is_equal(5)
	assert_int(_event_of(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED).reason) \
		.is_equal(EconomyEnums.FailReason.NO_STOCK)


# ============================================================================
# Debug inventory reset (Settings debug button)
# ============================================================================

func test_debug_set_inventory_sets_coins_and_every_booster() -> void:
	# Arrange: a depleted wallet (0 coins, 0 of every booster).
	var w = _make(0, 0, _config_with_start(0))
	# Act
	w.debug_set_inventory(1000, 3)
	# Assert
	assert_int(w.balance(COINS)).is_equal(1000)
	assert_int(w.booster_count(PICKER)).is_equal(3)
	assert_int(w.booster_count(RESHUFFLE)).is_equal(3)
	assert_int(w.booster_count(EXTRA_DISCARD)).is_equal(3)


func test_debug_set_inventory_overwrites_existing_higher_values() -> void:
	# Arrange: a wallet richer than the reset target.
	var w = _make(5000, 0, _config_with_start(9))
	# Act
	w.debug_set_inventory(1000, 3)
	# Assert: reset overwrites (does not add to) the existing values.
	assert_int(w.balance(COINS)).is_equal(1000)
	assert_int(w.booster_count(PICKER)).is_equal(3)


func test_debug_set_inventory_persists_and_survives_reload() -> void:
	# Arrange
	var w = _make(0, 0, _config_with_start(0))
	# Act
	w.debug_set_inventory(1000, 3)
	# Assert: values are mirrored into SaveData and restored by a fresh service.
	assert_int(_save_stub.data.wallet_coins).is_equal(1000)
	var w2 = auto_free(WALLET.new())
	w2.configure(_save_stub, StubCompliance.new(), FixedTimeProvider.new(), _config_with_start(0))
	assert_int(w2.balance(COINS)).is_equal(1000)
	assert_int(w2.booster_count(PICKER)).is_equal(3)


func test_debug_set_inventory_emits_stock_changed_per_booster() -> void:
	# Arrange
	var w = _make(0, 0, _config_with_start(0))
	var seen: Array = []
	w.booster_stock_changed.connect(func(t: int, n: int) -> void: seen.append([t, n]))
	# Act
	w.debug_set_inventory(1000, 3)
	# Assert: one refresh signal per booster type, each carrying the new count.
	assert_int(seen.size()).is_equal(3)
	for entry in seen:
		assert_int(entry[1]).is_equal(3)


func test_debug_set_inventory_clamps_coins_to_wallet_cap() -> void:
	# Arrange: a config with a small coin cap.
	var cfg := _config_with_start(0)
	cfg.coins_max = 500
	var w = _make(0, 0, cfg)
	# Act
	w.debug_set_inventory(1000, 3)
	# Assert: coins are clamped to the cap, never exceeding it.
	assert_int(w.balance(COINS)).is_equal(500)
