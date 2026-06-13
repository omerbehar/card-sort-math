extends GdUnitTestSuite
## Tests for [EconomyEvent] and [EconomyEnums] — S3-001 chain-head story.
##
## Coverage:
##   - Kind enum has exactly 9 values with the canonical names (enum-drift guard).
##   - Each static factory sets only its documented payload fields and leaves all
##     others at their sentinel defaults.
##   - No-arithmetic-solving: no result/operands/solution_text field exists on the class.
##   - EconomyEnums.BoosterType has exactly 3 values (PICKER, RESHUFFLE, EXTRA_DISCARD);
##     no UNDO, no HINT.
##   - EconomyEnums.EarnSource matches the registry canonical list (6 values).
##
## Source: design/gdd/deck-economy.md §Economy Events; ADR-0008.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns all payload fields other than [code]kind[/code] as a Dictionary,
## so tests can assert the full sentinel footprint in one place.
func _payload(e: EconomyEvent) -> Dictionary:
	return {
		"currency": e.currency,
		"amount": e.amount,
		"source": e.source,
		"new_balance": e.new_balance,
		"booster_type": e.booster_type,
		"reason": e.reason,
		"sku": e.sku,
	}


# ---------------------------------------------------------------------------
# Kind enum — drift guard
# ---------------------------------------------------------------------------

func test_kind_enum_has_exactly_9_values() -> void:
	# Arrange/Act
	var keys: Array = EconomyEvent.Kind.keys()
	# Assert (HINT_RESULT removed when Hint was replaced by Picker, 2026-06-13)
	assert_int(keys.size()).is_equal(9)


func test_kind_enum_contains_all_canonical_names() -> void:
	# Arrange: canonical names from design/gdd/deck-economy.md §Economy Events + ADR-0008.
	var expected: Array[String] = [
		"CURRENCY_EARNED",
		"CURRENCY_SPENT",
		"SPEND_FAILED",
		"EARN_CAP_REACHED",
		"TRANSACTION_ROLLED_BACK",
		"BOOSTER_ACTIVATED",
		"BOOSTER_PRECONDITION_FAILED",
		"BOOSTER_PURCHASE_FAILED",
		"IAP_BLOCKED",
	]
	var actual: Array = EconomyEvent.Kind.keys()
	# Assert: exact name set (order matters for serialisation stability)
	for name: String in expected:
		assert_bool(name in actual).is_true()
	assert_int(actual.size()).is_equal(expected.size())


func test_kind_enum_order_matches_canonical_definition() -> void:
	# Order is load-bearing (int indices used in serialised data / analytics).
	assert_int(EconomyEvent.Kind.CURRENCY_EARNED).is_equal(0)
	assert_int(EconomyEvent.Kind.CURRENCY_SPENT).is_equal(1)
	assert_int(EconomyEvent.Kind.SPEND_FAILED).is_equal(2)
	assert_int(EconomyEvent.Kind.EARN_CAP_REACHED).is_equal(3)
	assert_int(EconomyEvent.Kind.TRANSACTION_ROLLED_BACK).is_equal(4)
	assert_int(EconomyEvent.Kind.BOOSTER_ACTIVATED).is_equal(5)
	assert_int(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED).is_equal(6)
	assert_int(EconomyEvent.Kind.BOOSTER_PURCHASE_FAILED).is_equal(7)
	assert_int(EconomyEvent.Kind.IAP_BLOCKED).is_equal(8)


# ---------------------------------------------------------------------------
# Factory: currency_earned
# ---------------------------------------------------------------------------

func test_currency_earned_sets_kind_correctly() -> void:
	# Arrange/Act
	var e: EconomyEvent = EconomyEvent.currency_earned(
			EconomyEnums.Currency.COINS, 55, EconomyEnums.EarnSource.LEVEL_WIN, 455)
	# Assert
	assert_int(e.kind).is_equal(EconomyEvent.Kind.CURRENCY_EARNED)


func test_currency_earned_sets_all_four_payload_fields() -> void:
	# Arrange/Act
	var e: EconomyEvent = EconomyEvent.currency_earned(
			EconomyEnums.Currency.COINS, 55, EconomyEnums.EarnSource.LEVEL_WIN, 455)
	# Assert
	assert_int(e.currency).is_equal(EconomyEnums.Currency.COINS)
	assert_int(e.amount).is_equal(55)
	assert_int(e.source).is_equal(EconomyEnums.EarnSource.LEVEL_WIN)
	assert_int(e.new_balance).is_equal(455)


func test_currency_earned_leaves_non_payload_fields_at_sentinel() -> void:
	# Arrange/Act
	var e: EconomyEvent = EconomyEvent.currency_earned(
			EconomyEnums.Currency.COINS, 55, EconomyEnums.EarnSource.LEVEL_WIN, 455)
	# Assert: fields not in this Kind's payload are at sentinel
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: currency_spent
# ---------------------------------------------------------------------------

func test_currency_spent_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.currency_spent(EconomyEnums.Currency.COINS, 120, 80)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.CURRENCY_SPENT)


func test_currency_spent_sets_three_payload_fields() -> void:
	# Arrange/Act
	var e: EconomyEvent = EconomyEvent.currency_spent(EconomyEnums.Currency.COINS, 120, 80)
	# Assert
	assert_int(e.currency).is_equal(EconomyEnums.Currency.COINS)
	assert_int(e.amount).is_equal(120)
	assert_int(e.new_balance).is_equal(80)


func test_currency_spent_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.currency_spent(EconomyEnums.Currency.COINS, 120, 80)
	assert_int(e.source).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: spend_failed
# ---------------------------------------------------------------------------

func test_spend_failed_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.spend_failed(EconomyEnums.Currency.COINS, 120, 20)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.SPEND_FAILED)


func test_spend_failed_stores_balance_in_new_balance_field() -> void:
	# The balance-at-failure is stored in new_balance (reuse, documented in ADR-0008).
	var e: EconomyEvent = EconomyEvent.spend_failed(EconomyEnums.Currency.COINS, 120, 20)
	assert_int(e.currency).is_equal(EconomyEnums.Currency.COINS)
	assert_int(e.amount).is_equal(120)
	assert_int(e.new_balance).is_equal(20)


func test_spend_failed_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.spend_failed(EconomyEnums.Currency.COINS, 120, 20)
	assert_int(e.source).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: earn_cap_reached
# ---------------------------------------------------------------------------

func test_earn_cap_reached_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.earn_cap_reached(EconomyEnums.EarnSource.REWARDED_AD)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.EARN_CAP_REACHED)


func test_earn_cap_reached_sets_source_only() -> void:
	# Arrange/Act (single-arg form: reason defaults to the -1 sentinel)
	var e: EconomyEvent = EconomyEvent.earn_cap_reached(EconomyEnums.EarnSource.REWARDED_AD)
	# Assert: source set
	assert_int(e.source).is_equal(EconomyEnums.EarnSource.REWARDED_AD)
	# Assert: all other payload fields at sentinel
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


func test_earn_cap_reached_carries_optional_reason() -> void:
	# The optional reason disambiguates which cap blocked the earn (HUD messaging).
	var e: EconomyEvent = EconomyEvent.earn_cap_reached(
			EconomyEnums.EarnSource.REWARDED_AD, EconomyEnums.FailReason.AD_COUNT_CAP)
	assert_int(e.source).is_equal(EconomyEnums.EarnSource.REWARDED_AD)
	assert_int(e.reason).is_equal(EconomyEnums.FailReason.AD_COUNT_CAP)
	# Everything else still at sentinel.
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: transaction_rolled_back
# ---------------------------------------------------------------------------

func test_transaction_rolled_back_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.transaction_rolled_back(EconomyEnums.Currency.COINS, 250)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.TRANSACTION_ROLLED_BACK)


func test_transaction_rolled_back_sets_currency_and_amount() -> void:
	var e: EconomyEvent = EconomyEvent.transaction_rolled_back(EconomyEnums.Currency.COINS, 250)
	assert_int(e.currency).is_equal(EconomyEnums.Currency.COINS)
	assert_int(e.amount).is_equal(250)


func test_transaction_rolled_back_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.transaction_rolled_back(EconomyEnums.Currency.COINS, 250)
	assert_int(e.source).is_equal(-1)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: booster_activated
# ---------------------------------------------------------------------------

func test_booster_activated_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.booster_activated(EconomyEnums.BoosterType.PICKER)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.BOOSTER_ACTIVATED)


func test_booster_activated_sets_booster_type_only() -> void:
	var e: EconomyEvent = EconomyEvent.booster_activated(EconomyEnums.BoosterType.RESHUFFLE)
	assert_int(e.booster_type).is_equal(EconomyEnums.BoosterType.RESHUFFLE)
	# All other payload fields at sentinel
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.source).is_equal(-1)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.reason).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: booster_precondition_failed
# ---------------------------------------------------------------------------

func test_booster_precondition_failed_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.booster_precondition_failed(
			EconomyEnums.BoosterType.EXTRA_DISCARD, EconomyEnums.FailReason.DISCARD_FULL)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.BOOSTER_PRECONDITION_FAILED)


func test_booster_precondition_failed_sets_booster_type_and_reason() -> void:
	var e: EconomyEvent = EconomyEvent.booster_precondition_failed(
			EconomyEnums.BoosterType.EXTRA_DISCARD, EconomyEnums.FailReason.DISCARD_FULL)
	assert_int(e.booster_type).is_equal(EconomyEnums.BoosterType.EXTRA_DISCARD)
	assert_int(e.reason).is_equal(EconomyEnums.FailReason.DISCARD_FULL)


func test_booster_precondition_failed_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.booster_precondition_failed(
			EconomyEnums.BoosterType.RESHUFFLE, EconomyEnums.FailReason.WON_BOARD)
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.source).is_equal(-1)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# Factory: booster_purchase_failed
# ---------------------------------------------------------------------------

func test_booster_purchase_failed_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.booster_purchase_failed(
			EconomyEnums.BoosterType.PICKER, EconomyEnums.FailReason.INVALID_TARGET)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.BOOSTER_PURCHASE_FAILED)


func test_booster_purchase_failed_sets_booster_type_and_reason() -> void:
	var e: EconomyEvent = EconomyEvent.booster_purchase_failed(
			EconomyEnums.BoosterType.PICKER, EconomyEnums.FailReason.INVALID_TARGET)
	assert_int(e.booster_type).is_equal(EconomyEnums.BoosterType.PICKER)
	assert_int(e.reason).is_equal(EconomyEnums.FailReason.INVALID_TARGET)


func test_booster_purchase_failed_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.booster_purchase_failed(
			EconomyEnums.BoosterType.PICKER, EconomyEnums.FailReason.INVALID_TARGET)
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.source).is_equal(-1)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.sku).is_equal(-1)


# ---------------------------------------------------------------------------
# No-arithmetic-solving structural guard (Picker replaced Hint; no answer fields)
# ---------------------------------------------------------------------------

func test_event_class_has_no_result_field() -> void:
	var e: EconomyEvent = EconomyEvent.booster_activated(EconomyEnums.BoosterType.PICKER)
	assert_bool(e.get("result") == null).is_true()


func test_event_class_has_no_operands_field() -> void:
	var e: EconomyEvent = EconomyEvent.booster_activated(EconomyEnums.BoosterType.PICKER)
	assert_bool(e.get("operands") == null).is_true()


func test_event_class_has_no_solution_text_field() -> void:
	var e: EconomyEvent = EconomyEvent.booster_activated(EconomyEnums.BoosterType.PICKER)
	assert_bool(e.get("solution_text") == null).is_true()


# ---------------------------------------------------------------------------
# Factory: iap_blocked
# ---------------------------------------------------------------------------

func test_iap_blocked_sets_kind_correctly() -> void:
	var e: EconomyEvent = EconomyEvent.iap_blocked(3, EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)
	assert_int(e.kind).is_equal(EconomyEvent.Kind.IAP_BLOCKED)


func test_iap_blocked_sets_sku_and_reason() -> void:
	# SKU is a plain int (Sku enum deferred to M4 IAP work per ADR-0008).
	var e: EconomyEvent = EconomyEvent.iap_blocked(3, EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)
	assert_int(e.sku).is_equal(3)
	assert_int(e.reason).is_equal(EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)


func test_iap_blocked_leaves_non_payload_fields_at_sentinel() -> void:
	var e: EconomyEvent = EconomyEvent.iap_blocked(3, EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)
	assert_int(e.currency).is_equal(-1)
	assert_int(e.amount).is_equal(0)
	assert_int(e.source).is_equal(-1)
	assert_int(e.new_balance).is_equal(-1)
	assert_int(e.booster_type).is_equal(-1)


# ---------------------------------------------------------------------------
# EconomyEnums — BoosterType
# ---------------------------------------------------------------------------

func test_booster_type_enum_has_exactly_3_values() -> void:
	## Undo removed (2026-06-12); Hint replaced by Picker (2026-06-13).
	## The set is PICKER, RESHUFFLE, EXTRA_DISCARD only.
	assert_int(EconomyEnums.BoosterType.keys().size()).is_equal(3)


func test_booster_type_enum_contains_picker() -> void:
	assert_bool("PICKER" in EconomyEnums.BoosterType.keys()).is_true()


func test_booster_type_enum_does_not_contain_hint() -> void:
	## Hint was replaced by Picker (2026-06-13); must not reappear.
	assert_bool("HINT" in EconomyEnums.BoosterType.keys()).is_false()


func test_booster_type_enum_contains_reshuffle() -> void:
	assert_bool("RESHUFFLE" in EconomyEnums.BoosterType.keys()).is_true()


func test_booster_type_enum_contains_extra_discard() -> void:
	assert_bool("EXTRA_DISCARD" in EconomyEnums.BoosterType.keys()).is_true()


func test_booster_type_enum_does_not_contain_undo() -> void:
	## Undo was cut (2026-06-12); must never reappear silently.
	assert_bool("UNDO" in EconomyEnums.BoosterType.keys()).is_false()


# ---------------------------------------------------------------------------
# EconomyEnums — EarnSource
# ---------------------------------------------------------------------------

func test_earn_source_enum_has_exactly_6_values() -> void:
	## Canonical list from design/registry/entities.yaml EarnSource entry.
	assert_int(EconomyEnums.EarnSource.keys().size()).is_equal(6)


func test_earn_source_enum_contains_all_registry_values() -> void:
	## Values must match design/registry/entities.yaml EarnSource.values verbatim.
	var expected: Array[String] = [
		"LEVEL_WIN",
		"DAILY_CHALLENGE",
		"REWARDED_AD",
		"IAP",
		"MILESTONE_GIFT",
		"GEM_CONVERT",
	]
	var actual: Array = EconomyEnums.EarnSource.keys()
	for name: String in expected:
		assert_bool(name in actual).is_true()


# ---------------------------------------------------------------------------
# EconomyEnums — FailReason
# ---------------------------------------------------------------------------

func test_fail_reason_enum_has_exactly_9_values() -> void:
	# Picker replaced Hint (2026-06-13): the two Hint-only reasons
	# (ALREADY_IN_PROGRESS, NO_EXPOSED_CARD) were dropped and INVALID_TARGET added.
	assert_int(EconomyEnums.FailReason.keys().size()).is_equal(9)


func test_fail_reason_enum_contains_all_expected_values() -> void:
	var expected: Array[String] = [
		"INVALID_TARGET",
		"DISCARD_FULL",
		"AT_MAX",
		"WON_BOARD",
		"COMPLIANCE_RESTRICTED",
		"AD_COUNT_CAP",
		"DAILY_COIN_CAP",
		"GEM_CONVERT_CAP",
		"WALLET_FULL",
	]
	var actual: Array = EconomyEnums.FailReason.keys()
	for name: String in expected:
		assert_bool(name in actual).is_true()


func test_fail_reason_enum_does_not_contain_hint_reasons() -> void:
	## Hint-only reasons removed with the Picker swap (2026-06-13).
	var keys: Array = EconomyEnums.FailReason.keys()
	assert_bool("ALREADY_IN_PROGRESS" in keys).is_false()
	assert_bool("NO_EXPOSED_CARD" in keys).is_false()


func test_fail_reason_enum_does_not_contain_no_history() -> void:
	## NO_HISTORY was Undo-only; Undo is removed. Must never appear.
	assert_bool("NO_HISTORY" in EconomyEnums.FailReason.keys()).is_false()


# ---------------------------------------------------------------------------
# _to_string — debuggability
# ---------------------------------------------------------------------------

func test_to_string_includes_kind_name() -> void:
	var e: EconomyEvent = EconomyEvent.currency_earned(
			EconomyEnums.Currency.COINS, 55, EconomyEnums.EarnSource.LEVEL_WIN, 455)
	assert_str(e._to_string()).contains("CURRENCY_EARNED")


func test_to_string_includes_payload_values() -> void:
	var e: EconomyEvent = EconomyEvent.currency_spent(EconomyEnums.Currency.COINS, 120, 80)
	# The _to_string output should contain a payload value (the spend amount).
	assert_str(e._to_string()).contains("120")
