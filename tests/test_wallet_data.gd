extends GdUnitTestSuite
## Tests for [WalletData] — S3-002.
##
## Coverage:
##   - Non-negativity invariant: negative set → clamped to 0.
##   - balance_of / set_balance keyed on EconomyEnums.Currency.
##   - duplicate_wallet() produces an independent copy (mutations don't cross).
##   - to_dict / from_dict round-trip (exact values).
##   - from_dict({}) → safe defaults (coins 0, gems 0).
##   - Defensive from_dict: missing keys, negative values, null-tolerant.
##
## Source: design/gdd/deck-economy.md §Core Rule 3;
##         design/registry/entities.yaml WalletData entry.


# ---------------------------------------------------------------------------
# Non-negativity invariant (direct property assignment)
# ---------------------------------------------------------------------------

func test_coins_negative_set_clamped_to_zero() -> void:
	# Arrange
	var w := WalletData.new()
	# Act
	w.coins = -100
	# Assert
	assert_int(w.coins).is_equal(0)


func test_gems_negative_set_clamped_to_zero() -> void:
	# Arrange
	var w := WalletData.new()
	# Act
	w.gems = -1
	# Assert
	assert_int(w.gems).is_equal(0)


func test_coins_zero_set_stays_zero() -> void:
	var w := WalletData.new()
	w.coins = 0
	assert_int(w.coins).is_equal(0)


func test_coins_positive_set_stores_value() -> void:
	var w := WalletData.new()
	w.coins = 500
	assert_int(w.coins).is_equal(500)


func test_gems_positive_set_stores_value() -> void:
	var w := WalletData.new()
	w.gems = 42
	assert_int(w.gems).is_equal(42)


# ---------------------------------------------------------------------------
# balance_of / set_balance keyed on EconomyEnums.Currency
# ---------------------------------------------------------------------------

func test_balance_of_coins_returns_coin_balance() -> void:
	# Arrange
	var w := WalletData.new()
	w.coins = 200
	# Act / Assert
	assert_int(w.balance_of(EconomyEnums.Currency.COINS)).is_equal(200)


func test_balance_of_gems_returns_gem_balance() -> void:
	var w := WalletData.new()
	w.gems = 15
	assert_int(w.balance_of(EconomyEnums.Currency.GEMS)).is_equal(15)


func test_balance_of_unknown_currency_returns_zero() -> void:
	var w := WalletData.new()
	w.coins = 100
	w.gems = 50
	assert_int(w.balance_of(99)).is_equal(0)


func test_set_balance_coins_stores_positive_value() -> void:
	# Arrange
	var w := WalletData.new()
	# Act
	w.set_balance(EconomyEnums.Currency.COINS, 750)
	# Assert
	assert_int(w.coins).is_equal(750)


func test_set_balance_gems_stores_positive_value() -> void:
	var w := WalletData.new()
	w.set_balance(EconomyEnums.Currency.GEMS, 30)
	assert_int(w.gems).is_equal(30)


func test_set_balance_coins_negative_clamped_to_zero() -> void:
	# Arrange
	var w := WalletData.new()
	w.coins = 100
	# Act
	w.set_balance(EconomyEnums.Currency.COINS, -50)
	# Assert
	assert_int(w.coins).is_equal(0)


func test_set_balance_gems_negative_clamped_to_zero() -> void:
	var w := WalletData.new()
	w.gems = 20
	w.set_balance(EconomyEnums.Currency.GEMS, -1)
	assert_int(w.gems).is_equal(0)


func test_set_balance_coins_zero_stores_zero() -> void:
	var w := WalletData.new()
	w.coins = 100
	w.set_balance(EconomyEnums.Currency.COINS, 0)
	assert_int(w.coins).is_equal(0)


# ---------------------------------------------------------------------------
# duplicate_wallet — independence (EC-09 rollback contract)
# ---------------------------------------------------------------------------

func test_duplicate_wallet_coins_matches_original() -> void:
	# Arrange
	var original := WalletData.new()
	original.coins = 300
	original.gems = 12
	# Act
	var copy := original.duplicate_wallet()
	# Assert
	assert_int(copy.coins).is_equal(300)
	assert_int(copy.gems).is_equal(12)


func test_duplicate_wallet_mutating_copy_does_not_change_original_coins() -> void:
	# Arrange
	var original := WalletData.new()
	original.coins = 300
	# Act
	var copy := original.duplicate_wallet()
	copy.coins = 999
	# Assert: original is unchanged
	assert_int(original.coins).is_equal(300)


func test_duplicate_wallet_mutating_copy_does_not_change_original_gems() -> void:
	var original := WalletData.new()
	original.gems = 5
	var copy := original.duplicate_wallet()
	copy.gems = 0
	assert_int(original.gems).is_equal(5)


func test_duplicate_wallet_mutating_original_does_not_change_copy() -> void:
	# Arrange
	var original := WalletData.new()
	original.coins = 100
	var copy := original.duplicate_wallet()
	# Act
	original.coins = 0
	# Assert: the snapshot copy is unaffected
	assert_int(copy.coins).is_equal(100)


func test_duplicate_wallet_returns_different_instance() -> void:
	var original := WalletData.new()
	var copy := original.duplicate_wallet()
	assert_bool(copy != original).is_true()


# ---------------------------------------------------------------------------
# to_dict / from_dict round-trip
# ---------------------------------------------------------------------------

func test_to_dict_from_dict_round_trips_coins() -> void:
	# Arrange
	var w := WalletData.new()
	w.coins = 12345
	w.gems = 7
	# Act
	var restored := WalletData.from_dict(w.to_dict())
	# Assert
	assert_int(restored.coins).is_equal(12345)


func test_to_dict_from_dict_round_trips_gems() -> void:
	var w := WalletData.new()
	w.coins = 10
	w.gems = 88
	var restored := WalletData.from_dict(w.to_dict())
	assert_int(restored.gems).is_equal(88)


func test_to_dict_contains_coins_key() -> void:
	var keys: Array = WalletData.new().to_dict().keys()
	assert_bool(keys.has("coins")).is_true()


func test_to_dict_contains_gems_key() -> void:
	var keys: Array = WalletData.new().to_dict().keys()
	assert_bool(keys.has("gems")).is_true()


# ---------------------------------------------------------------------------
# from_dict — defensive / edge cases
# ---------------------------------------------------------------------------

func test_from_dict_empty_dict_defaults_coins_to_zero() -> void:
	var w := WalletData.from_dict({})
	assert_int(w.coins).is_equal(0)


func test_from_dict_empty_dict_defaults_gems_to_zero() -> void:
	var w := WalletData.from_dict({})
	assert_int(w.gems).is_equal(0)


func test_from_dict_missing_gems_key_defaults_to_zero() -> void:
	var w := WalletData.from_dict({"coins": 50})
	assert_int(w.gems).is_equal(0)


func test_from_dict_missing_coins_key_defaults_to_zero() -> void:
	var w := WalletData.from_dict({"gems": 3})
	assert_int(w.coins).is_equal(0)


func test_from_dict_negative_coins_clamped_to_zero() -> void:
	var w := WalletData.from_dict({"coins": -999, "gems": 0})
	assert_int(w.coins).is_equal(0)


func test_from_dict_negative_gems_clamped_to_zero() -> void:
	var w := WalletData.from_dict({"coins": 0, "gems": -1})
	assert_int(w.gems).is_equal(0)


func test_from_dict_zero_values_stored_correctly() -> void:
	var w := WalletData.from_dict({"coins": 0, "gems": 0})
	assert_int(w.coins).is_equal(0)
	assert_int(w.gems).is_equal(0)
