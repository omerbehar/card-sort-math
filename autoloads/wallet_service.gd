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

const DEFAULT_CONFIG_PATH: String = "res://assets/data/economy_config.tres"

# --- injected dependencies (resolve to autoloads in _ready if not configured) ---
var _save = null                    # SaveService (has `data: SaveData` + save_game())
var _compliance = null              # ComplianceService (used by S3-005; stored for forward use)
var _time: TimeProvider = null      # injectable clock (S3-005 daily caps use it)
var _config: EconomyConfig = null   # tuning knobs (coins_max/gems_max here)

# --- wallet state ---
var _wallet: WalletData = WalletData.new()

# --- per-level economy state (cleared on level boundary) ---
var reshuffle_count: int = 0
var boosters_used_this_level: int = 0
var extra_discard_active: bool = false
var _hint_in_progress: bool = false


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


## Activates the Hint booster on [param board] (Core Rule 8, Formula 5).
##
## Precondition checks (in order — no spend before any precondition fails):
## 1. [member _hint_in_progress] — rejects double-tap (EC-08, AC-H04).
## 2. [method BoardModel.exposed_cards] empty — no card to hint (AC-H03).
## 3. [method spend] — deducts [member EconomyConfig.hint_cost_coins] (AC-H01).
##
## On success: sets [member _hint_in_progress], increments
## [member boosters_used_this_level], emits [code]HINT_RESULT(card_id)[/code]
## then [code]BOOSTER_ACTIVATED(HINT)[/code], returns the hinted card_id.
##
## [b]No-arithmetic-solving (AC-M01a):[/b] emits card_id ONLY via
## [method EconomyEvent.hint_result]. No result, operands, or solution_text
## is ever forwarded.
##
## Returns [code]-1[/code] on any failure (precondition or insufficient funds).
func use_hint(board: BoardModel) -> int:
	if _hint_in_progress:
		economy_event.emit(EconomyEvent.booster_purchase_failed(
				EconomyEnums.BoosterType.HINT,
				EconomyEnums.FailReason.ALREADY_IN_PROGRESS))
		return -1  # EC-08 / AC-H04: no second spend
	if board.exposed_cards().is_empty():
		economy_event.emit(EconomyEvent.booster_precondition_failed(
				EconomyEnums.BoosterType.HINT,
				EconomyEnums.FailReason.NO_EXPOSED_CARD))
		return -1  # AC-H03: coins unchanged
	if not spend(EconomyEnums.Currency.COINS, _config.hint_cost_coins):
		return -1  # insufficient -> SPEND_FAILED already emitted by spend()
	_hint_in_progress = true
	boosters_used_this_level += 1
	var card_id: int = HintScore.best_card(
			board,
			_config.routes_weight,
			_config.opens_weight,
			_config.relief_weight)
	economy_event.emit(EconomyEvent.hint_result(card_id))          # AC-M01a: card_id ONLY
	economy_event.emit(EconomyEvent.booster_activated(EconomyEnums.BoosterType.HINT))
	return card_id


## Clears the in-progress Hint flag once the view has consumed the highlight
## (EC-08). Call this when the highlighted card is tapped or the level ends.
func notify_hint_consumed() -> void:
	_hint_in_progress = false


## Clears the per-level economy state. Called on a new level (GameManager.level_started,
## connected at runtime) and directly by tests. Accepts an optional level argument so it
## can be bound straight to the [code]level_started(level: int)[/code] signal.
func reset_level_state(_level: int = 0) -> void:
	reshuffle_count = 0
	boosters_used_this_level = 0
	extra_discard_active = false
	_hint_in_progress = false
