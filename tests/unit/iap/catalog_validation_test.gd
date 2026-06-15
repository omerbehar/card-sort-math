extends GdUnitTestSuite
## Validation tests for the IAP catalog resource (S4-006).
##
## Loads the authored [code]assets/data/iap_catalog.tres[/code] and exercises [IAPCatalog]
## validation + the remote-config [method IAPCatalog.from_dict] path (S4-005 shape). New
## classes are referenced via preloaded consts (global-class-cache-safe).

const CATALOG := preload("res://data/iap_catalog.gd")
const ENTRY := preload("res://data/iap_catalog_entry.gd")
const CATALOG_TRES := "res://assets/data/iap_catalog.tres"


func _entry(sku: int, kind: int, currency: int, amount: int, price: int):
	var e = ENTRY.new()
	e.sku_id = sku
	e.kind = kind
	e.currency = currency
	e.amount = amount
	e.price_cents = price
	return e


# ---------------------------------------------------------------------------
# Authored catalog (.tres)
# ---------------------------------------------------------------------------

func test_authored_catalog_loads_and_validates() -> void:
	var cat = load(CATALOG_TRES)
	assert_object(cat).is_not_null()
	assert_bool(cat is CATALOG).is_true()
	assert_array(cat.validate()).is_empty()  # no validation errors
	assert_bool(cat.is_valid()).is_true()


func test_authored_catalog_skus_unique_and_kinds_correct() -> void:
	var cat = load(CATALOG_TRES)
	var ids: Array = cat.ids()
	# Unique ids (size of a de-duplicated set equals the list size).
	var unique: Dictionary = {}
	for id: int in ids:
		unique[id] = true
	assert_int(unique.size()).is_equal(ids.size())

	var rt: Dictionary = cat.to_runtime_dict()
	# Remove-Ads (sku 1) is a non-consumable entitlement; currency packs are consumable.
	assert_int(rt[1]["kind"]).is_equal(ENTRY.Kind.NON_CONSUMABLE_ENTITLEMENT)
	assert_int(rt[100]["kind"]).is_equal(ENTRY.Kind.CONSUMABLE_CURRENCY)
	assert_int(rt[100]["amount"]).is_equal(500)
	assert_int(rt[200]["currency"]).is_equal(EconomyEnums.Currency.GEMS)


# ---------------------------------------------------------------------------
# Validation rules
# ---------------------------------------------------------------------------

func test_validate_flags_duplicate_sku_ids() -> void:
	var cat = CATALOG.new()
	cat.entries.append(_entry(1, ENTRY.Kind.NON_CONSUMABLE_ENTITLEMENT, 0, 0, 299))
	cat.entries.append(_entry(1, ENTRY.Kind.CONSUMABLE_CURRENCY, 0, 500, 99))  # dup id
	assert_bool(cat.is_valid()).is_false()


func test_validate_flags_currency_pack_with_nonpositive_amount() -> void:
	var cat = CATALOG.new()
	cat.entries.append(_entry(100, ENTRY.Kind.CONSUMABLE_CURRENCY, 0, 0, 99))  # amount 0
	assert_bool(cat.is_valid()).is_false()


func test_validate_flags_unknown_kind() -> void:
	var cat = CATALOG.new()
	cat.entries.append(_entry(5, 99, 0, 0, 99))  # kind out of range
	assert_bool(cat.is_valid()).is_false()


func test_empty_catalog_is_valid_and_safe() -> void:
	var cat = CATALOG.new()
	assert_bool(cat.is_valid()).is_true()
	assert_array(cat.ids()).is_empty()
	assert_int(cat.to_runtime_dict().size()).is_equal(0)


# ---------------------------------------------------------------------------
# Remote-config load path (S4-005 shape)
# ---------------------------------------------------------------------------

func test_from_dict_builds_remote_loaded_catalog() -> void:
	# The shape a JsonRemoteConfigSource transport would return (string keys, JSON dicts).
	var data: Dictionary = {
		"1": {"kind": 1, "currency": 0, "amount": 0, "price_cents": 299},
		"100": {"kind": 0, "currency": 0, "amount": 500, "price_cents": 99},
	}
	var cat = CATALOG.from_dict(data)
	assert_int(cat.ids().size()).is_equal(2)
	assert_bool(cat.is_valid()).is_true()
	var rt: Dictionary = cat.to_runtime_dict()
	assert_int(rt[1]["kind"]).is_equal(ENTRY.Kind.NON_CONSUMABLE_ENTITLEMENT)
	assert_int(rt[100]["amount"]).is_equal(500)


func test_from_dict_skips_non_dict_values() -> void:
	var data: Dictionary = {"100": {"kind": 0, "amount": 500, "price_cents": 99}, "junk": 42}
	var cat = CATALOG.from_dict(data)
	assert_int(cat.ids().size()).is_equal(1)  # the scalar "junk" entry is skipped
