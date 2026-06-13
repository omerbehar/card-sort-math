class_name WalletData
extends RefCounted
## Pure, node-free record of the player's currency balances.
##
## Implements GDD Core Rule 3 (design/gdd/deck-economy.md §Core Rules §Currencies).
## Persisted via [SaveData.wallet_coins] and [SaveData.wallet_gems] (schema v2).
##
## [b]Responsibility split:[/b]
## [WalletData] enforces a single invariant: balances are always [code]>= 0[/code].
## The [b]upper cap[/b] ([code]COINS_MAX[/code] / [code]GEMS_MAX[/code]) is a
## designer-tunable knob in [EconomyConfig] and is applied by [code]WalletService.earn()[/code]
## (S3-004, Formula 4). Clamping the cap here would hard-code a tuning value into core/,
## violating the gameplay-code rules. See also EC-09 (design/gdd/deck-economy.md): the
## atomic rollback path restores a pre-spend snapshot via [b]direct assignment[/b] into
## this record — never via [code]earn()[/code], which would silently truncate near
## [code]MAX_BALANCE[/code]. [WalletData] itself must not impose the upper bound so that
## rollback is always exact.
##
## All reads and writes go through [WalletService] (autoloads/); callers must not
## mutate balances directly except via [method set_balance].

## Soft-currency balance (Coins). Always >= 0; upper cap applied by WalletService.
var coins: int = 0:
	set(value):
		coins = maxi(0, value)

## Hard-currency balance (Gems). Always >= 0; upper cap applied by WalletService.
var gems: int = 0:
	set(value):
		gems = maxi(0, value)


## Returns the balance for [param currency] (an [EconomyEnums.Currency] value).
## Returns [code]0[/code] for any unknown currency index.
func balance_of(currency: int) -> int:
	match currency:
		EconomyEnums.Currency.COINS:
			return coins
		EconomyEnums.Currency.GEMS:
			return gems
		_:
			return 0


## Sets the balance for [param currency] to [param value], clamped to [code]>= 0[/code].
## The caller (WalletService) is responsible for applying the upper cap.
func set_balance(currency: int, value: int) -> void:
	match currency:
		EconomyEnums.Currency.COINS:
			coins = maxi(0, value)
		EconomyEnums.Currency.GEMS:
			gems = maxi(0, value)


## Returns an independent copy of this wallet record (deep value copy).
##
## A general-purpose snapshot utility for callers/tests that need to compare or
## restore whole-wallet state. [b]Note:[/b] [code]WalletService.spend()[/code]'s
## EC-09 rollback does NOT use this — it snapshots the single affected balance as
## a plain [int] and restores it via [method set_balance] (cheaper, and the spend
## only ever touches one currency). The exact-restore guarantee (never via
## [code]earn()[/code], which would truncate near the cap) holds either way.
func duplicate_wallet() -> WalletData:
	var copy := WalletData.new()
	copy.coins = coins
	copy.gems = gems
	return copy


## Serialises this wallet to a plain [Dictionary] suitable for JSON.
func to_dict() -> Dictionary:
	return {
		"coins": coins,
		"gems": gems,
	}


## Builds a [WalletData] from a parsed dictionary.
## Missing keys default to [code]0[/code]; negative values are clamped to [code]0[/code];
## null / non-numeric values coerce to [code]0[/code]. Never crashes on bad or empty
## input — mirrors [SaveData]'s defensive style ([code]int(null)[/code] raises in GDScript).
static func from_dict(d: Dictionary) -> WalletData:
	var w := WalletData.new()
	w.coins = maxi(0, _as_int(d.get("coins", 0)))
	w.gems = maxi(0, _as_int(d.get("gems", 0)))
	return w


# Coerces a Variant to int, treating null and non-numeric values as 0.
# Required because int(null) / int("x") raise in GDScript — a corrupt dict must
# not crash (mirrors SaveData._safe_int).
static func _as_int(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0
