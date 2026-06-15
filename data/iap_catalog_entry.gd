class_name IAPCatalogEntryResource
extends Resource
## One product in the IAP catalog (S4-006). Authored in [code]assets/data/iap_catalog.tres[/code]
## and consumed by [IAPService] (which maps it to its runtime entry on a successful purchase).
##
## A consumable currency pack grants [member amount] of [member currency]; a non-consumable
## entitlement (Remove-Ads) grants the entitlement and ignores currency/amount. [member price_cents]
## is the store price tier in USD cents — display/telemetry only, never used in grant logic.
##
## Source: GAME_PLAN §8 (IAP catalog); ADR-0014 §2; production/sprints/sprint-04.md S4-006.

## Product kind — mirrors [IAPService].ProductKind by ordinal so the runtime mapping is direct.
enum Kind {
	CONSUMABLE_CURRENCY,        ## Currency pack: grants [member amount] of [member currency].
	NON_CONSUMABLE_ENTITLEMENT, ## Remove-Ads: grants the entitlement; currency/amount unused.
}

## Stable SKU token (matches the [IAPService] SKU_* constants). Must be unique in a catalog.
@export var sku_id: int = 0
## Whether this product is a consumable currency pack or a non-consumable entitlement.
@export var kind: Kind = Kind.CONSUMABLE_CURRENCY
## [EconomyEnums.Currency] to grant (currency packs only): 0 = COINS, 1 = GEMS.
@export var currency: int = 0
## Amount of [member currency] to grant (currency packs only); must be > 0 for a pack.
@export var amount: int = 0
## Store price tier in USD cents (display/telemetry only). Must be > 0.
@export var price_cents: int = 0
