extends Node
## Autoload: the atomic wallet transaction core for the Deck Economy (ADR-0008).
##
## Owns the player's [WalletData] (coins + gems), mirrored to [SaveData.wallet_coins]
## / [SaveData.wallet_gems] and persisted on every mutation via [SaveService]. Every
## currency outcome is reported through the single typed [signal economy_event]
## ([EconomyEvent]); the HUD and Analytics subscribe to it. This type is the seam the
## boosters (S3-006/007/009), daily caps + compliance (S3-005), and earn triggers
## (S3-008) build on.
##
## All dependencies are injected via [method configure] (SaveService, ComplianceService,
## [TimeProvider], [EconomyConfig]) so the transaction logic is unit-testable with no
## autoload coupling — mirroring [GameManager]/[ComplianceService]. In normal play they
## resolve to the autoloads in [method _ready].
##
## [b]Booster inventory (prototype):[/b] owned per-booster counts persist in [SaveData]
## ([code]boosters_picker/reshuffle/extra_discard[/code]), seeded once from
## [member EconomyConfig.starting_booster_count]. A buff is consumed for free on use;
## at zero the UI offers a watch-ad / pay-coins top-up. This diverges from the GDD's
## coins-per-use booster model — see design/gdd/deck-economy.md §Prototype Addendum.
##
## [b]Atomicity / rollback (EC-09):[/b] [method spend] takes an optional [code]on_committed[/code]
## [Callable] — the board mutation the spend pays for. GDScript has no exceptions, so a
## board mutation that "raises" (GDD EC-09) is modelled as the Callable returning [code]false[/code].
## On a [code]false[/code] return the pre-spend balance is restored by [b]direct snapshot
## assignment[/b] (NEVER via [method earn], which carries daily-cap/compliance side effects,
## needs a bogus source, and would emit a spurious credit) and a
## [code]TRANSACTION_ROLLED_BACK[/code] event is emitted.
##
## Source: design/gdd/deck-economy.md §Core Rule 4, Formula 3/4, EC-09/14; ADR-0008.

## The single typed economy signal. HUD + Analytics subscribe; never carries board state.
signal economy_event(event: EconomyEvent)

## Emitted when an owned booster count changes (grant / consume / seed). Lets the HUD
## refresh the per-booster count badge. Prototype buff inventory; see [member _booster_stock].
signal booster_stock_changed(booster_type: int, new_count: int)

const DEFAULT_CONFIG_PATH: String = "res://assets/data/economy_config.tres"

# --- injected dependencies (resolve to autoloads in _ready if not configured) ---
var _save = null                    # SaveService (has `data: SaveData` + save_game())
var _compliance = null              # ComplianceService (used by S3-005; stored for forward use)
var _time: TimeProvider = null      # injectable clock (S3-005 daily caps use it)
var _config: EconomyConfig = null   # tuning knobs (coins_max/gems_max here)

# --- wallet state ---
var _wallet: WalletData = WalletData.new()

# --- booster inventory (prototype: owned counts) ---
# Each booster is consumed for free on use; at zero the UI offers a watch-ad /
# pay-coins top-up. Counts persist in SaveData (boosters_picker/reshuffle/extra_discard),
# seeded once from EconomyConfig.starting_booster_count (SaveData.boosters_seeded gate).
# Maps each EconomyEnums.BoosterType to its SaveData field name.
const _BOOSTER_FIELD: Dictionary = {
	EconomyEnums.BoosterType.PICKER: "boosters_picker",
	EconomyEnums.BoosterType.RESHUFFLE: "boosters_reshuffle",
	EconomyEnums.BoosterType.EXTRA_DISCARD: "boosters_extra_discard",
}

# --- per-level economy state (cleared on level boundary) ---
var reshuffle_count: int = 0
var boosters_used_this_level: int = 0
var extra_discard_active: bool = false
# Captured at each level boundary so the Reshuffle seed (Formula 6) is stable across
# all reshuffles of a level (level_id + level_start_timestamp + reshuffle_count).
var _level_id: int = 0
var _level_start_ts: int = 0


func _ready() -> void:
	if _save == null:
		_save = SaveService
	if _compliance == null:
		_compliance = ComplianceService
	if _time == null:
		_time = TimeProvider.new()
	if _config == null:
		_config = load(DEFAULT_CONFIG_PATH)
	_load_wallet()
	_seed_booster_stock()
	_connect_game_manager()


## Injects dependencies and reloads the wallet from the save. Intended for tests:
## [code]wallet.configure(save, compliance, time, config)[/code]. Normal play uses the
## autoloads automatically via [method _ready].
func configure(save: Object, compliance: Object, time: TimeProvider, config: EconomyConfig) -> void:
	_save = save
	_compliance = compliance
	_time = time
	_config = config
	_load_wallet()
	_seed_booster_stock()


# Builds the in-memory wallet from the persisted SaveData fields.
func _load_wallet() -> void:
	_wallet = WalletData.new()
	if _save != null and _save.data != null:
		_wallet.coins = int(_save.data.wallet_coins)
		_wallet.gems = int(_save.data.wallet_gems)


# Mirrors the wallet back into SaveData and persists. No-op if no save is wired.
func _persist() -> void:
	if _save == null or _save.data == null:
		return
	_save.data.wallet_coins = _wallet.coins
	_save.data.wallet_gems = _wallet.gems
	_save.save_game()


# Connects per-level reset to GameManager.level_started at runtime. Guarded so a
# directly-instantiated (non-tree) test node never touches the autoload graph.
# NB: GameManager autoloads are NOT engine singletons, so Engine.has_singleton()
# would wrongly return false — resolve the node by its /root path instead.
func _connect_game_manager() -> void:
	if not is_inside_tree():
		return
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.has_signal("level_started") \
			and not gm.level_started.is_connected(reset_level_state):
		gm.level_started.connect(reset_level_state)
	# Level-win coin earn (S3-008): GameManager has no star scoring yet (S2-011
	# deferred), so the live wiring grants the flat-fallback win reward. Unit tests
	# call grant_level_win(stars) directly to exercise the star-weighted path.
	if gm.has_signal("level_completed") \
			and not gm.level_completed.is_connected(_on_level_completed):
		gm.level_completed.connect(_on_level_completed)


# --- queries ---

## Current balance for [param currency] (an [EconomyEnums.Currency] value).
func balance(currency: int) -> int:
	return _wallet.balance_of(currency)


## Coin cost of [param booster_type] (an [EconomyEnums.BoosterType]) from the config.
## Lets the HUD show costs / afford-state without reaching into [EconomyConfig].
func booster_coin_cost(booster_type: int) -> int:
	match booster_type:
		EconomyEnums.BoosterType.PICKER:
			return _config.picker_cost_coins
		EconomyEnums.BoosterType.RESHUFFLE:
			return _config.reshuffle_cost_coins
		EconomyEnums.BoosterType.EXTRA_DISCARD:
			return _config.extra_discard_cost_coins
		_:
			return 0


# --- booster inventory (prototype: owned counts) ---------------------------

# Seeds each booster's owned count from EconomyConfig.starting_booster_count, exactly
# once per save (SaveData.boosters_seeded gate) so a new/migrated player gets the
# starting stock but a player who spent down to 0 is not topped back up. Persists.
func _seed_booster_stock() -> void:
	if _save == null or _save.data == null or _save.data.boosters_seeded:
		return
	var start: int = _config.starting_booster_count if _config != null else 0
	for type: int in _BOOSTER_FIELD:
		_save.data.set(_BOOSTER_FIELD[type], maxi(0, start))
	_save.data.boosters_seeded = true
	_persist()


## Owned count of [param booster_type] (an [EconomyEnums.BoosterType]). Drives the
## HUD count badge and the "tap → use for free vs. show top-up popup" decision.
## Persisted in SaveData; 0 when no save is wired.
func booster_count(booster_type: int) -> int:
	if _save == null or _save.data == null or not _BOOSTER_FIELD.has(booster_type):
		return 0
	return maxi(0, int(_save.data.get(_BOOSTER_FIELD[booster_type])))


## Adds [param n] to the owned count of [param booster_type] (e.g. a watch-ad reward
## or a coin purchase). Persists and emits [signal booster_stock_changed]. No-op for
## n <= 0 or when no save is wired.
func grant_booster(booster_type: int, n: int = 1) -> void:
	if n <= 0 or _save == null or _save.data == null or not _BOOSTER_FIELD.has(booster_type):
		return
	var new_count: int = booster_count(booster_type) + n
	_save.data.set(_BOOSTER_FIELD[booster_type], new_count)
	_persist()
	booster_stock_changed.emit(booster_type, new_count)


## Decrements the owned count of [param booster_type] by one if any are owned.
## Returns true if a unit was consumed; false when the count is already zero.
## Persists and emits [signal booster_stock_changed] on success.
func consume_booster(booster_type: int) -> bool:
	var have: int = booster_count(booster_type)
	if have <= 0:
		return false
	_save.data.set(_BOOSTER_FIELD[booster_type], have - 1)
	_persist()
	booster_stock_changed.emit(booster_type, have - 1)
	return true


## [b]Debug only.[/b] Forces the wallet to a known state: sets coins to [param coins]
## (clamped to the wallet cap) and every booster's owned count to [param boosters_each].
## Persists and emits [signal booster_stock_changed] for each booster so the HUD count
## badges refresh. Deliberately bypasses the earn/spend policy layer (caps, compliance,
## analytics) and emits no [signal economy_event] — the coin display is refreshed by the
## caller — so this never pollutes the live economy or its telemetry. Wired to the
## Settings debug button, which is itself gated behind [method OS.is_debug_build].
func debug_set_inventory(coins: int, boosters_each: int) -> void:
	if _save == null or _save.data == null:
		return
	_wallet.coins = clampi(coins, 0, _cap_for(EconomyEnums.Currency.COINS))
	var n: int = maxi(0, boosters_each)
	for booster_type: int in _BOOSTER_FIELD:
		_save.data.set(_BOOSTER_FIELD[booster_type], n)
	_persist()
	for booster_type: int in _BOOSTER_FIELD:
		booster_stock_changed.emit(booster_type, n)


# Per-currency hard cap from the tuning config (Formula 4).
func _cap_for(currency: int) -> int:
	match currency:
		EconomyEnums.Currency.COINS:
			return _config.coins_max
		EconomyEnums.Currency.GEMS:
			return _config.gems_max
		_:
			return 0


# --- transactions ---

## Routes [param amount] of [param currency] through the policy layer, then
## delegates to [method _earn_raw] for the actual balance mutation (Formula 4).
## Returns the [b]actual[/b] amount credited (after policy + clamp).
## A 0-or-negative amount is a logic-error guard (EC-14): no mutation, no event, returns 0.
##
## Policy routing (S3-005 / design/gdd/deck-economy.md Rule 15, Rule 21):
## - [constant EconomyEnums.EarnSource.REWARDED_AD] → compliance + daily-cap gate via [method _earn_rewarded_ad].
##   [b]Rewarded ads always pay out in COINS[/b]: the [param currency] argument is
##   ignored on this path (the GDD has no gem-paying ad). Callers pass COINS.
## - All other sources (LEVEL_WIN, DAILY_CHALLENGE, MILESTONE_GIFT, GEM_CONVERT, IAP) → raw,
##   uncapped, ungated (AC-C03 / AC-CH01).
func earn(currency: int, amount: int, source: int) -> int:
	if amount <= 0:
		return 0  # EC-14
	if source == EconomyEnums.EarnSource.REWARDED_AD:
		return _earn_rewarded_ad(amount)
	return _earn_raw(currency, amount, source)


# Raw, uncapped, ungated credit — the actual balance mutation (Formula 4).
# Extracted from the original earn() body so _earn_rewarded_ad() and
# convert_gems_to_coins() can call it after their own policy checks.
func _earn_raw(currency: int, amount: int, source: int) -> int:
	if amount <= 0:
		return 0
	var current: int = _wallet.balance_of(currency)
	var headroom: int = maxi(0, _cap_for(currency) - current)
	var actual: int = mini(amount, headroom)
	if actual <= 0:
		return 0  # already at cap — nothing credited, no event
	var new_balance: int = current + actual
	_wallet.set_balance(currency, new_balance)
	_persist()
	economy_event.emit(EconomyEvent.currency_earned(currency, actual, source, new_balance))
	return actual


## Grants the coin reward for a level win (Formula 1 + 1b). Returns the actual coins
## credited (after the wallet cap clamp). Emits a single [code]CURRENCY_EARNED(LEVEL_WIN)[/code]
## for the summed total.
##
## Reward = base + first-win bonus + clean-clear bonus, where:
## - base = [method _base_win_coins] ([param stars] → BASE_WIN_COINS, else the flat fallback).
## - first-win bonus ([member EconomyConfig.first_win_bonus]) applies once per UTC day —
##   the first win whose [member SaveData.wins_today] is still 0 (AC-EF01/EF02).
## - clean-clear bonus ([member EconomyConfig.clean_clear_bonus]) applies only when
##   [member boosters_used_this_level] == 0 and the knob is > 0 (Formula 1b / AC-EFF01-03).
##
## LEVEL_WIN income is uncapped and ungated — it flows through [method earn] which routes
## non-ad sources straight to the raw credit (AC-C03 / AC-CH01). [param stars] is the
## 1–3 star rating from the Scoring system (S2-011); until that ships the live
## [signal GameManager.level_completed] wiring passes 0 → flat fallback.
## Source: design/gdd/deck-economy.md Formula 1/1b, Rule 13; AC-EF01/EF02, AC-EFF01-03.
func grant_level_win(stars: int = 0) -> int:
	_roll_day_if_needed()
	var total: int = _base_win_coins(stars)
	if _is_first_win_today():
		total += _config.first_win_bonus
	if _config.clean_clear_bonus > 0 and boosters_used_this_level == 0:
		total += _config.clean_clear_bonus
	var credited: int = earn(
			EconomyEnums.Currency.COINS, total, EconomyEnums.EarnSource.LEVEL_WIN)
	_record_win_today()
	return credited


# Star-weighted base reward (Formula 1). A 1–3 star rating maps to its configured
# coin value; any other value (notably 0 = "no star scoring yet", S2-011 deferred)
# falls back to coins_win_flat_fallback so no earn value is ever hardcoded.
func _base_win_coins(stars: int) -> int:
	match stars:
		1:
			return _config.coins_win_1_star
		2:
			return _config.coins_win_2_star
		3:
			return _config.coins_win_3_star
		_:
			return _config.coins_win_flat_fallback


# True if no level has been won yet on the current UTC day (drives first_win_bonus).
# Conservatively true when no save is wired (DI incomplete) so the bonus is not lost.
func _is_first_win_today() -> bool:
	if _save == null or _save.data == null:
		return true
	return _save.data.wins_today == 0


# Records that a win happened today (after the day-roll has run). Persisted so the
# once-per-day first-win bonus survives an app restart within the same UTC day.
func _record_win_today() -> void:
	if _save == null or _save.data == null:
		return
	_save.data.wins_today += 1
	_persist()


# GameManager.level_completed handler — grants the flat-fallback win reward (stars
# unavailable until S2-011). Signature matches level_completed(level: int).
func _on_level_completed(_level: int = 0) -> void:
	grant_level_win()


# Rolls the daily counters to zero if the UTC day has advanced since they were last
# written (design/gdd/deck-economy.md Rule 15 / Formula 8 / Rule 21).
# Guard: silently skips if _save, _save.data, or _time is null (incomplete DI).
func _roll_day_if_needed() -> void:
	if _save == null or _save.data == null or _time == null:
		return
	var today: int = _time.utc_day_key()
	if _save.data.daily_key != today:
		_save.data.ad_coins_today = 0
		_save.data.ads_watched_today = 0
		_save.data.gems_converted_today = 0
		_save.data.wins_today = 0
		_save.data.daily_key = today
		_persist()


# Gated ad earn: compliance + per-day count cap + per-day coin cap (Rule 15, Formula 8).
# Returns actual coins credited (0 on any block).
# Source: design/gdd/deck-economy.md AC-C01/C02/CH02/CL02.
func _earn_rewarded_ad(amount: int) -> int:
	_roll_day_if_needed()
	# Compliance gate — child / restricted users: silent block, no event (AC-CH02 / AC-CL02).
	if _compliance != null and _compliance.is_restricted():
		return 0
	# Count cap: max rewarded ads per day (Formula 8).
	if _save != null and _save.data != null \
			and _save.data.ads_watched_today >= _config.max_ads_per_day:
		economy_event.emit(EconomyEvent.earn_cap_reached(
				EconomyEnums.EarnSource.REWARDED_AD, EconomyEnums.FailReason.AD_COUNT_CAP))
		return 0
	# Coin cap: daily_coins_cap applies to REWARDED_AD income only (Rule 15 canonical scope).
	var remaining: int = 0
	if _save != null and _save.data != null:
		remaining = _config.daily_coins_cap - _save.data.ad_coins_today
	else:
		remaining = _config.daily_coins_cap
	if remaining <= 0:
		economy_event.emit(EconomyEvent.earn_cap_reached(
				EconomyEnums.EarnSource.REWARDED_AD, EconomyEnums.FailReason.DAILY_COIN_CAP))
		return 0  # AC-C01
	# Partial cap earn: clamp to remaining headroom (AC-C02 / EC-11).
	var credited: int = _earn_raw(
			EconomyEnums.Currency.COINS,
			mini(amount, remaining),
			EconomyEnums.EarnSource.REWARDED_AD)
	# Wallet hard cap (coins_max) can swallow the credit even with daily headroom left.
	# Don't consume an ad view for nothing — surface WALLET_FULL and leave counters be.
	if credited <= 0:
		economy_event.emit(EconomyEvent.earn_cap_reached(
				EconomyEnums.EarnSource.REWARDED_AD, EconomyEnums.FailReason.WALLET_FULL))
		return 0
	if _save != null and _save.data != null:
		_save.data.ad_coins_today += credited
		_save.data.ads_watched_today += 1
		_persist()
	return credited


## Converts [param gems_amount] gems to coins at the penalised rate (Formula 7,
## Rule 21). Returns [code]true[/code] on success, [code]false[/code] on any failure.
##
## Failure paths (no balance change on false return):
## - [param gems_amount] <= 0 → false, no event (EC-14).
## - daily_gem_convert_cap exceeded → false, [code]EARN_CAP_REACHED(GEM_CONVERT, GEM_CONVERT_CAP)[/code] (AC-GC02 / EC-13).
## - coin wallet too full to hold the full payout → false, [code]EARN_CAP_REACHED(GEM_CONVERT, WALLET_FULL)[/code].
##   Checked [b]before[/b] the gem spend so gems are never burned for a truncated payout.
## - insufficient gem balance → false, [code]SPEND_FAILED[/code] (AC-GC03).
##
## On success: gems spent, coins credited, [member SaveData.gems_converted_today] incremented.
## Source: design/gdd/deck-economy.md Rule 21, Formula 7, AC-GC01..GC03.
func convert_gems_to_coins(gems_amount: int) -> bool:
	if gems_amount <= 0:
		return false  # EC-14 — no event
	_roll_day_if_needed()
	# Daily gem conversion cap (Rule 21 / Formula 7). Uses its own cap, NOT daily_coins_cap.
	if _save != null and _save.data != null \
			and _save.data.gems_converted_today + gems_amount > _config.daily_gem_convert_cap:
		economy_event.emit(EconomyEvent.earn_cap_reached(
				EconomyEnums.EarnSource.GEM_CONVERT, EconomyEnums.FailReason.GEM_CONVERT_CAP))
		return false  # AC-GC02 / EC-13
	# Coin-wallet headroom check BEFORE spending gems: the conversion must be atomic in
	# value terms. If coins_max can't hold the full penalised payout, abort without
	# burning gems (the gems-spent-then-coins-truncated path would silently lose value).
	var coins: int = gems_amount * _config.gem_to_coin_rate
	if balance(EconomyEnums.Currency.COINS) + coins > _cap_for(EconomyEnums.Currency.COINS):
		economy_event.emit(EconomyEvent.earn_cap_reached(
				EconomyEnums.EarnSource.GEM_CONVERT, EconomyEnums.FailReason.WALLET_FULL))
		return false
	# Atomic spend first — insufficient gems emits SPEND_FAILED (AC-GC03).
	if not spend(EconomyEnums.Currency.GEMS, gems_amount):
		return false
	# Credit coins at the penalised rate (GEM_CONVERT is NOT subject to daily_coins_cap — AC-C03).
	_earn_raw(EconomyEnums.Currency.COINS, coins, EconomyEnums.EarnSource.GEM_CONVERT)
	if _save != null and _save.data != null:
		_save.data.gems_converted_today += gems_amount
		_persist()
	return true


## Initiates an IAP purchase for [param sku]. Gated by [method ComplianceService.is_restricted]:
## restricted (CHILD / UNKNOWN) users are blocked before [code]IAPService[/code] is ever called.
##
## Returns [code]true[/code] if the IAP flow may proceed; [code]false[/code] if blocked.
## On block: [code]IAP_BLOCKED(sku, COMPLIANCE_RESTRICTED)[/code] emitted, gems unchanged (AC-CL01).
## IAPService integration is deferred to M4; this method is the compliance chokepoint stub.
## Source: design/gdd/deck-economy.md Rule 5/6, AC-CL01, EC-12.
func initiate_iap(sku: int) -> bool:
	if _compliance != null and _compliance.is_restricted():
		economy_event.emit(EconomyEvent.iap_blocked(sku, EconomyEnums.FailReason.COMPLIANCE_RESTRICTED))
		return false
	# IAPService.purchase(sku) deferred to M4 — stub returns true (flow may proceed).
	return true


## Returns whether a rewarded ad earn is currently available (Formula 8 / Rule 15).
## True only when the player is not restricted, has not hit the ad count cap, and
## has not hit the daily coin cap. Intended for HUD availability checks.
##
## [b]Side effect:[/b] runs [method _roll_day_if_needed] first, so on a UTC day
## boundary this query resets the daily counters and persists the save. The write
## is idempotent (at most once per day), but callers should be aware this is not a
## pure read.
## Source: design/gdd/deck-economy.md Formula 8, AC-C01.
func is_ad_earn_available() -> bool:
	_roll_day_if_needed()
	if _compliance != null and _compliance.is_restricted():
		return false
	if _save == null or _save.data == null:
		return true
	return _save.data.ads_watched_today < _config.max_ads_per_day \
		and _save.data.ad_coins_today < _config.daily_coins_cap


## Atomically spends [param amount] of [param currency] (Formula 3). Returns true on
## success. A 0-or-negative amount returns false with NO event (EC-14 guard). Insufficient
## funds returns false and emits [code]SPEND_FAILED[/code] without mutating.
##
## [param on_committed] is the optional board mutation this spend pays for. Because GDScript
## has no exceptions, a failed mutation is signalled by the Callable returning [code]false[/code]:
## the pre-spend balance is then restored by direct snapshot assignment (EC-09 — never via
## [method earn]) and a [code]TRANSACTION_ROLLED_BACK[/code] event is emitted.
func spend(currency: int, amount: int, on_committed := Callable()) -> bool:
	if amount <= 0:
		return false  # EC-14 / AC-W04: caller bug, silent guard
	var snapshot: int = _wallet.balance_of(currency)  # EC-09 pre-spend snapshot
	if snapshot < amount:
		economy_event.emit(EconomyEvent.spend_failed(currency, amount, snapshot))
		return false
	_wallet.set_balance(currency, snapshot - amount)
	economy_event.emit(EconomyEvent.currency_spent(currency, amount, _wallet.balance_of(currency)))
	if on_committed.is_valid():
		var ok: bool = bool(on_committed.call())
		if not ok:
			_wallet.set_balance(currency, snapshot)  # exact direct restore — NOT earn()
			economy_event.emit(EconomyEvent.transaction_rolled_back(currency, amount))
			_persist()
			return false
	_persist()
	return true


## Activates the Picker booster: plays the covered card [param card_id] the player
## chose, bypassing the coverage rule (replaces Hint). Returns the ordered
## [code]Array[GameEvent][/code] for the view to animate, or an empty array on
## failure (invalid target or insufficient funds).
##
## Precondition checks (in order — no spend before any precondition fails):
## 1. Valid target — the board is not over and the card is still on the floor
##    → else [code]BOOSTER_PRECONDITION_FAILED(PICKER, INVALID_TARGET)[/code].
## 2. [method spend] — deducts [member EconomyConfig.picker_cost_coins].
##
## On success: increments [member boosters_used_this_level], plays the card via
## [method BoardModel.pick_card], emits [code]BOOSTER_ACTIVATED(PICKER)[/code].
##
## [b]No-arithmetic-solving:[/b] the pick resolves to board [GameEvent]s (route /
## discard); no arithmetic answer is ever computed or revealed.
func use_picker(board: BoardModel, card_id: int) -> Array[GameEvent]:
	if not _picker_target_valid(board, card_id):
		return []
	if not spend(EconomyEnums.Currency.COINS, _config.picker_cost_coins):
		return []  # insufficient -> SPEND_FAILED already emitted by spend()
	return _activate_picker(board, card_id)


## Picker activated from the owned-stock count (prototype buff inventory) instead of
## paying coins: consumes one Picker and plays the chosen covered card. Returns the
## board [GameEvent]s, or [] if the target is invalid or no Picker is owned.
func use_picker_from_stock(board: BoardModel, card_id: int) -> Array[GameEvent]:
	if not _picker_target_valid(board, card_id):
		return []
	if not consume_booster(EconomyEnums.BoosterType.PICKER):
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.PICKER, EconomyEnums.FailReason.NO_STOCK))
		return []
	return _activate_picker(board, card_id)


# Picker precondition (EC-08): valid only while the board is live and the chosen
# card is still on the floor. Emits INVALID_TARGET on failure.
func _picker_target_valid(board: BoardModel, card_id: int) -> bool:
	if board.is_game_over() or board.is_card_removed(card_id):
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.PICKER,
				EconomyEnums.FailReason.INVALID_TARGET))
		return false
	return true


# Shared Picker activation (no payment): counts the use and plays the card. Never
# reveals an arithmetic answer — board.pick_card resolves to route/discard events.
func _activate_picker(board: BoardModel, card_id: int) -> Array[GameEvent]:
	boosters_used_this_level += 1
	var events: Array[GameEvent] = board.pick_card(card_id)
	economy_event.emit(EconomyEvent.booster_activated(EconomyEnums.BoosterType.PICKER))
	return events


## Activates the Reshuffle booster on [param board] (Core Rule 10, Formula 6, ADR-0009).
## [param placements] is the level layout (passed in — autoloads load it, [code]core/[/code]
## does not). Returns the new placement→card assignment ([code]Array[int][/code]) on success
## so the view can re-place cards, or an [b]empty array[/b] on failure.
##
## Precondition: the board must not be in a WIN state (EC-15, AC-R05) — else
## [code]BOOSTER_PRECONDITION_FAILED(RESHUFFLE, WON_BOARD)[/code], no spend, [code][][/code].
## On success: increments [member reshuffle_count], spends
## [member EconomyConfig.reshuffle_cost_coins], derives the seed via
## [method ReshuffleSeed.mix] (level_id + captured level_start_timestamp +
## reshuffle_count) into a fresh RNG, re-permutes the floor coverage via
## [method BoardModel.reshuffle] (routable-card guarantee, AC-R09), and emits
## [code]BOOSTER_ACTIVATED(RESHUFFLE)[/code]. The timestamp comes from the injected
## [TimeProvider] (AC-R04/R08) captured in [method reset_level_state].
func use_reshuffle(board: BoardModel, placements: Array) -> Array[int]:
	if not _reshuffle_allowed(board):
		return []  # EC-15 / AC-R05
	if not spend(EconomyEnums.Currency.COINS, _config.reshuffle_cost_coins):
		return []  # insufficient -> SPEND_FAILED already emitted
	return _activate_reshuffle(board, placements)


## Reshuffle activated from the owned-stock count (prototype buff inventory) instead
## of paying coins: consumes one Reshuffle and re-permutes the floor. Returns the new
## placement→card assignment, or [] if the board is won or no Reshuffle is owned.
func use_reshuffle_from_stock(board: BoardModel, placements: Array) -> Array[int]:
	if not _reshuffle_allowed(board):
		return []
	if not consume_booster(EconomyEnums.BoosterType.RESHUFFLE):
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.RESHUFFLE, EconomyEnums.FailReason.NO_STOCK))
		return []
	return _activate_reshuffle(board, placements)


# Reshuffle precondition (EC-15 / AC-R05): not allowed on an already-won board.
func _reshuffle_allowed(board: BoardModel) -> bool:
	if board.is_won():
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.RESHUFFLE,
				EconomyEnums.FailReason.WON_BOARD))
		return false
	return true


# Shared Reshuffle activation (no payment): derives the deterministic seed (Formula 6),
# re-permutes coverage (routable-card guarantee), and counts the use.
func _activate_reshuffle(board: BoardModel, placements: Array) -> Array[int]:
	reshuffle_count += 1
	var seed: int = ReshuffleSeed.mix(_level_id, _level_start_ts, reshuffle_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var assignment: Array[int] = board.reshuffle(placements, rng)
	boosters_used_this_level += 1
	economy_event.emit(EconomyEvent.booster_activated(EconomyEnums.BoosterType.RESHUFFLE))
	return assignment


## Activates the Extra Discard Slot booster on [param board] (Core Rule 11, ADR-0010).
## [b]Purchase-ahead-only:[/b] a proactive buy made while room remains — deliberately
## NOT a one-tap-from-LOSE rescue.
##
## Precondition checks (in order — no spend before any precondition fails):
## 1. At cap: [method BoardModel.active_discard_slots] >= [member EconomyConfig.max_discard_slots]
##    → [code]BOOSTER_PRECONDITION_FAILED(EXTRA_DISCARD, AT_MAX)[/code] (EC-07, AC-E04).
## 2. Row full: [method BoardModel.occupied_discard_count] >= active slots
##    → [code]BOOSTER_PRECONDITION_FAILED(EXTRA_DISCARD, DISCARD_FULL)[/code] (EC-06, AC-E05).
## 3. [method spend] — deducts [member EconomyConfig.extra_discard_cost_coins].
##
## The cap lives here, not in [BoardModel] ([method BoardModel.expand_discard] is uncapped) so
## [code]core/[/code] stays free of economy config (ADR-0010). On success: appends one slot,
## sets [member extra_discard_active], increments [member boosters_used_this_level], emits
## [code]BOOSTER_ACTIVATED(EXTRA_DISCARD)[/code]. Returns [code]true[/code] on success, else false.
## Source: design/gdd/deck-economy.md Core Rule 11, EC-06/07, AC-E01/E03/E04/E05/E06; ADR-0010.
func use_extra_discard(board: BoardModel) -> bool:
	if not _extra_discard_allowed(board):
		return false
	if not spend(EconomyEnums.Currency.COINS, _config.extra_discard_cost_coins):
		return false  # insufficient -> SPEND_FAILED already emitted by spend()
	return _activate_extra_discard(board)


## Extra Discard activated from the owned-stock count (prototype buff inventory)
## instead of paying coins: consumes one and appends a discard slot. Returns true on
## success, false if a precondition fails (at max / row full) or none is owned.
func use_extra_discard_from_stock(board: BoardModel) -> bool:
	if not _extra_discard_allowed(board):
		return false
	if not consume_booster(EconomyEnums.BoosterType.EXTRA_DISCARD):
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.EXTRA_DISCARD, EconomyEnums.FailReason.NO_STOCK))
		return false
	return _activate_extra_discard(board)


# Extra Discard preconditions (EC-06/07): not at the slot cap, and the row is not
# already full (purchase-ahead-only — no one-tap-from-LOSE rescue).
func _extra_discard_allowed(board: BoardModel) -> bool:
	if board.active_discard_slots() >= _config.max_discard_slots:
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.EXTRA_DISCARD,
				EconomyEnums.FailReason.AT_MAX))
		return false  # EC-07 / AC-E04
	if board.occupied_discard_count() >= board.active_discard_slots():
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.EXTRA_DISCARD,
				EconomyEnums.FailReason.DISCARD_FULL))
		return false  # EC-06 / AC-E05
	return true


# Shared Extra Discard activation (no payment): appends a slot, flags the level, counts the use.
func _activate_extra_discard(board: BoardModel) -> bool:
	board.expand_discard()
	extra_discard_active = true
	boosters_used_this_level += 1
	economy_event.emit(EconomyEvent.booster_activated(EconomyEnums.BoosterType.EXTRA_DISCARD))
	return true


## Clears the per-level economy state. Called on a new level (GameManager.level_started,
## connected at runtime) and directly by tests. [param level] is the level id (bound
## straight from the [code]level_started(level: int)[/code] signal); it and the
## injected clock are captured so the Reshuffle seed (Formula 6) is stable across all
## reshuffles of this level.
func reset_level_state(level: int = 0) -> void:
	reshuffle_count = 0
	boosters_used_this_level = 0
	extra_discard_active = false
	_level_id = level
	_level_start_ts = _time.unix_seconds() if _time != null else 0
