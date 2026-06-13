class_name EconomyEvent
extends RefCounted
## A single economy outcome produced by [WalletService].
##
## This type is entirely separate from [GameEvent] (board domain). The two
## event channels are deliberately disjoint: [GameEvent] runs board → view
## replay (ADR-0002); [EconomyEvent] runs wallet → HUD + Analytics. They
## never share a type, a signal, or a consumer.
##
## [WalletService] exposes [code]signal economy_event(event: EconomyEvent)[/code];
## HUD and Analytics subscribe to it.
##
## Payload fields are plain [int] so this class stays a leaf with no dependency
## on [EconomyEnums] or any economy-config resource. Callers cast to the
## appropriate enum (e.g. [EconomyEnums.Currency]) when reading a field.
## Sentinel values: [code]-1[/code] when a field is not applicable for a given
## [enum Kind]; [code]amount[/code] defaults to [code]0[/code].
##
## [b]AC-M01a (hard rule):[/b] [method hint_result] sets ONLY [member card_id].
## No [code]result[/code], [code]operands[/code], or [code]solution_text[/code]
## field exists on this class. This is a structural compile-time guardrail for
## the no-arithmetic-solving pillar — the Hint booster must never expose the
## card's computed answer.
##
## Source: design/gdd/deck-economy.md §Economy Events (canonical table);
##         ADR-0008 (Key Interfaces); design/registry/entities.yaml.


## The canonical set of economy event kinds. Exactly 10 values; this order is
## load-bearing — tests assert the full key set by name (AC-M01a validation).
enum Kind {
	CURRENCY_EARNED,             ## earn() credited a balance. Payload: currency, amount (actual post-clamp), source, new_balance.
	CURRENCY_SPENT,              ## spend() deducted a balance. Payload: currency, amount, new_balance.
	SPEND_FAILED,                ## spend() rejected (insufficient funds). Payload: currency, amount, new_balance (reports the current balance).
	EARN_CAP_REACHED,            ## A daily cap blocked an earn. Payload: source.
	TRANSACTION_ROLLED_BACK,     ## A mid-transaction error restored the pre-spend balance. Payload: currency, amount.
	BOOSTER_ACTIVATED,           ## A booster successfully activated (after spend). Payload: booster_type.
	BOOSTER_PRECONDITION_FAILED, ## A booster precondition was unmet; no spend occurred. Payload: booster_type, reason.
	BOOSTER_PURCHASE_FAILED,     ## A purchase was rejected (e.g. double-tap). Payload: booster_type, reason.
	HINT_RESULT,                 ## Hint resolved to a target card. Payload: card_id ONLY (AC-M01a).
	IAP_BLOCKED,                 ## A restricted user's IAP attempt was blocked. Payload: sku, reason.
}

## Which economy outcome this event reports. See [enum Kind].
var kind: Kind
## Which currency is involved. Indexes [EconomyEnums.Currency]. [code]-1[/code] when N/A.
var currency: int = -1
## Coin or gem amount (actual post-clamp for earns; requested amount for spends/failures).
var amount: int = 0
## Earn provenance. Indexes [EconomyEnums.EarnSource]. [code]-1[/code] when N/A.
var source: int = -1
## Balance after the transaction (or current balance at failure time). [code]-1[/code] when N/A.
var new_balance: int = -1
## Which booster. Indexes [EconomyEnums.BoosterType]. [code]-1[/code] when N/A.
var booster_type: int = -1
## Failure reason. Indexes [EconomyEnums.FailReason]. [code]-1[/code] when N/A.
var reason: int = -1
## Card identifier for HINT_RESULT. [code]-1[/code] when N/A.
## [b]This is the ONLY field set by [method hint_result] (AC-M01a).[/b]
var card_id: int = -1
## Internal SKU token for IAP_BLOCKED. Plain int (Sku enum deferred to M4 IAP work). [code]-1[/code] when N/A.
var sku: int = -1


# ---------------------------------------------------------------------------
# Static factory constructors — one per Kind, mirroring GameEvent style.
# Only the documented payload fields are set; all others remain at their
# sentinel defaults, ensuring every Kind has a clean, testable footprint.
# ---------------------------------------------------------------------------

## Emitted by [method WalletService.earn] when a balance is credited.
## [param currency]: [EconomyEnums.Currency] value.
## [param amount]: actual coins/gems credited (post-cap clamp).
## [param source]: [EconomyEnums.EarnSource] value.
## [param new_balance]: balance after the credit.
static func currency_earned(
		p_currency: int,
		p_amount: int,
		p_source: int,
		p_new_balance: int,
) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.CURRENCY_EARNED
	e.currency = p_currency
	e.amount = p_amount
	e.source = p_source
	e.new_balance = p_new_balance
	return e


## Emitted by [method WalletService.spend] when a balance is successfully deducted.
## [param currency]: [EconomyEnums.Currency] value.
## [param amount]: coins/gems deducted.
## [param new_balance]: balance after the deduction.
static func currency_spent(
		p_currency: int,
		p_amount: int,
		p_new_balance: int,
) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.CURRENCY_SPENT
	e.currency = p_currency
	e.amount = p_amount
	e.new_balance = p_new_balance
	return e


## Emitted by [method WalletService.spend] when insufficient funds prevent a deduction.
## [param currency]: [EconomyEnums.Currency] value.
## [param amount]: the requested spend amount that was rejected.
## [param balance]: the current balance at rejection time (stored in [member new_balance]).
static func spend_failed(
		p_currency: int,
		p_amount: int,
		p_balance: int,
) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.SPEND_FAILED
	e.currency = p_currency
	e.amount = p_amount
	e.new_balance = p_balance  # reuses new_balance to report current balance at failure
	return e


## Emitted when a daily cap (or the wallet hard cap) prevents an earn.
## [param p_source]: [EconomyEnums.EarnSource] that triggered the cap.
## [param p_reason]: optional [EconomyEnums.FailReason] disambiguating which cap
## was hit (AD_COUNT_CAP / DAILY_COIN_CAP / GEM_CONVERT_CAP / WALLET_FULL).
## Defaults to [code]-1[/code] (unspecified) for back-compatible callers.
static func earn_cap_reached(p_source: int, p_reason: int = -1) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.EARN_CAP_REACHED
	e.source = p_source
	e.reason = p_reason
	return e


## Emitted when a mid-transaction board-mutation error triggers a balance rollback.
## The balance is restored by direct snapshot assignment (not via earn() — see EC-09).
## [param currency]: [EconomyEnums.Currency] value.
## [param amount]: the amount that was rolled back.
static func transaction_rolled_back(p_currency: int, p_amount: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.TRANSACTION_ROLLED_BACK
	e.currency = p_currency
	e.amount = p_amount
	return e


## Emitted after a booster spend succeeds and the booster activates.
## [param p_booster_type]: [EconomyEnums.BoosterType] value.
static func booster_activated(p_booster_type: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.BOOSTER_ACTIVATED
	e.booster_type = p_booster_type
	return e


## Emitted when a booster's precondition is unmet; no spend occurred.
## [param p_booster_type]: [EconomyEnums.BoosterType] value.
## [param p_reason]: [EconomyEnums.FailReason] value.
static func booster_precondition_failed(p_booster_type: int, p_reason: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.BOOSTER_PRECONDITION_FAILED
	e.booster_type = p_booster_type
	e.reason = p_reason
	return e


## Emitted when a booster purchase is rejected (e.g. double-tap while in-progress).
## [param p_booster_type]: [EconomyEnums.BoosterType] value.
## [param p_reason]: [EconomyEnums.FailReason] value.
static func booster_purchase_failed(p_booster_type: int, p_reason: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.BOOSTER_PURCHASE_FAILED
	e.booster_type = p_booster_type
	e.reason = p_reason
	return e


## Emitted when the Hint booster resolves to a target card.
## [b]AC-M01a (HARD RULE):[/b] sets ONLY [member card_id].
## All other payload fields remain at their sentinel defaults (-1 / 0).
## This factory is the structural compile-time guardrail ensuring the
## no-arithmetic-solving pillar: no result, operands, or solution_text
## can be emitted by this event kind.
## [param p_card_id]: the stable LevelConfig-assigned card identifier of the hint target.
static func hint_result(p_card_id: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.HINT_RESULT
	e.card_id = p_card_id
	return e


## Emitted when a restricted user's IAP attempt is blocked by ComplianceService.
## [param p_sku]: internal SKU token (int; Sku enum deferred to M4 IAP work).
## [param p_reason]: [EconomyEnums.FailReason] value (typically COMPLIANCE_RESTRICTED).
static func iap_blocked(p_sku: int, p_reason: int) -> EconomyEvent:
	var e := EconomyEvent.new()
	e.kind = Kind.IAP_BLOCKED
	e.sku = p_sku
	e.reason = p_reason
	return e


## Returns a human-readable representation for debugging. Mirrors GameEvent._to_string().
func _to_string() -> String:
	return "EconomyEvent(%s currency=%d amount=%d source=%d new_balance=%d booster_type=%d reason=%d card_id=%d sku=%d)" % [
		Kind.keys()[kind],
		currency, amount, source, new_balance,
		booster_type, reason, card_id, sku,
	]
