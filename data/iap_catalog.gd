class_name IAPCatalog
extends Resource
## The IAP product catalog (S4-006): the data-driven source of SKUs for [IAPService], so no
## SKU id, grant amount, or price is hardcoded in purchase logic.
##
## Authored as [code]assets/data/iap_catalog.tres[/code] (currency packs + bundles + the
## Remove-Ads SKU, GAME_PLAN §8). Also constructible from a plain [Dictionary] via
## [method from_dict] — the shape a [JsonRemoteConfigSource] transport returns (S4-005) — so
## the catalog is remote-config-loadable with the same merge story as [EconomyConfig].
##
## Source: GAME_PLAN §8; ADR-0014 §2; production/sprints/sprint-04.md S4-006.

## Preloaded so the entry type resolves regardless of global-class-cache timing.
const EntryResource := preload("res://data/iap_catalog_entry.gd")

## The products offered. Each is an [IAPCatalogEntryResource] (typed via the preloaded
## const so the type resolves regardless of global-class-cache timing).
@export var entries: Array[EntryResource] = []


## Returns the list of SKU ids in declaration order.
func ids() -> Array[int]:
	var out: Array[int] = []
	for e in entries:
		if e != null:
			out.append(e.sku_id)
	return out


## Validates the catalog and returns a list of human-readable error strings; an empty
## list means the catalog is well-formed. Checks: no null entries, unique SKU ids, a valid
## [enum IAPCatalogEntryResource.Kind], currency packs grant a positive amount, and every
## entry has a positive price tier.
func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for e in entries:
		if e == null:
			errors.append("null entry in catalog")
			continue
		if seen.has(e.sku_id):
			errors.append("duplicate sku_id %d" % e.sku_id)
		seen[e.sku_id] = true
		match e.kind:
			EntryResource.Kind.CONSUMABLE_CURRENCY:
				if e.amount <= 0:
					errors.append("sku %d: consumable currency must grant amount > 0" % e.sku_id)
			EntryResource.Kind.NON_CONSUMABLE_ENTITLEMENT:
				pass  # entitlement: currency/amount intentionally unused
			_:
				errors.append("sku %d: unknown kind %d" % [e.sku_id, e.kind])
		if e.price_cents <= 0:
			errors.append("sku %d: price_cents must be > 0" % e.sku_id)
	return errors


## True when [method validate] finds no problems.
func is_valid() -> bool:
	return validate().is_empty()


## Flattens the catalog to a plain runtime dictionary keyed by SKU id:
## [code]{ sku_id: { "kind": int, "currency": int, "amount": int } }[/code].
## [IAPService] builds its runtime entries from this (price is not part of grant logic).
func to_runtime_dict() -> Dictionary:
	var out: Dictionary = {}
	for e in entries:
		if e != null:
			out[e.sku_id] = {"kind": e.kind, "currency": e.currency, "amount": e.amount}
	return out


## Builds a catalog from a plain [Dictionary] — the shape a remote/JSON transport returns
## (S4-005). Keys are SKU ids (string or int); each value is a per-SKU dict with
## [code]kind/currency/amount/price_cents[/code]. Non-dictionary values are skipped. The
## result should still be checked with [method validate] before use.
static func from_dict(data: Dictionary) -> Resource:
	# Instantiate self via runtime load() rather than the bare class_name, which is not
	# guaranteed resolvable while this script is itself being compiled (global-class-cache).
	var cat = load("res://data/iap_catalog.gd").new()
	var built: Array[EntryResource] = []
	for key in data:
		var raw: Variant = data[key]
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var e := EntryResource.new()
		e.sku_id = int(key) if str(key).is_valid_int() else int(d.get("sku_id", 0))
		e.kind = int(d.get("kind", 0))
		e.currency = int(d.get("currency", 0))
		e.amount = int(d.get("amount", 0))
		e.price_cents = int(d.get("price_cents", 0))
		built.append(e)
	cat.entries = built
	return cat
