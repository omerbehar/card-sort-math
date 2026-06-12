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
	if gm != null and gm.has_signal("level_started") \
			and not gm.level_started.is_connected(reset_level_state):
		gm.level_started.connect(reset_level_state)


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

## Credits [param amount] of [param currency], clamped to the per-currency cap
## (Formula 4). Returns the [b]actual[/b] amount credited (after the clamp).
## A 0-or-negative amount is a logic-error guard (EC-14): no mutation, no event, returns 0.
## Daily caps + compliance gating wrap this in S3-005 — this is the raw, uncapped-by-source earn.
func earn(currency: int, amount: int, source: int) -> int:
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


## Clears the per-level economy state. Called on a new level (GameManager.level_started,
## connected at runtime) and directly by tests. Accepts an optional level argument so it
## can be bound straight to the [code]level_started(level: int)[/code] signal.
func reset_level_state(_level: int = 0) -> void:
	reshuffle_count = 0
	boosters_used_this_level = 0
	extra_discard_active = false
