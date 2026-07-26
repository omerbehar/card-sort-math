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

@export_group("Display (S5-001)")
## Player-facing offer title shown on the shop card (also serves as the localization key
## until a string table lands). Must be non-empty for a purchasable offer.
@export var display_name: String = ""
## Short grant summary shown under the title (e.g. "500 coins", "Removes ads").
@export var grant_summary: String = ""
## Path to the offer icon (Kenney skin / booster icon set); empty falls back to a default.
@export var icon_path: String = ""


## Formats [member price_cents] as a mock localized price string (e.g. "$2.99"). Real
## builds substitute the store SDK's localized price; the view never hardcodes a price.
func price_display() -> String:
	return "$%d.%02d" % [price_cents / 100, price_cents % 100]

