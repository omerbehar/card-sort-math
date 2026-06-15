class_name SaveData
extends RefCounted
## Pure, node-free player save state with (de)serialization and schema migration.
##
## Holds everything persisted between runs. [method to_dict] / [method from_dict]
## are the serialization seam; [SaveService] performs the actual file I/O. Keeping
## this class pure (no [Node], no file access) makes save / load / migration fully
## unit-testable (see [code]tests/test_save_data.gd[/code]) per ADR-0001.
##
## Persisted fields: [member schema_version], [member current_level],
## [member age_band], [member settings], [member tutorial_seen],
## [member wallet_coins], [member wallet_gems],
## [member daily_key], [member ad_coins_today],
## [member ads_watched_today], [member gems_converted_today], [member wins_today],
## [member boosters_picker], [member boosters_reshuffle], [member boosters_extra_discard],
## [member boosters_seeded],
## [member consent_personalized_ads], [member consent_analytics], [member consent_iap],
## [member consent_captured], [member consent_version],
## [member remove_ads_owned].

## Bump when the persisted shape changes, and add a step to [method _migrate].
const CURRENT_SCHEMA_VERSION: int = 6

## Audience band from the neutral age gate (see ADR-0005). Drives ad / analytics /
## IAP behaviour via the future ComplianceService.
enum AgeBand { UNKNOWN, ADULT, CHILD }

var schema_version: int = CURRENT_SCHEMA_VERSION
var current_level: int = 1
var age_band: AgeBand = AgeBand.UNKNOWN
var settings: Settings = Settings.new()
## Whether the player has already seen the first-time tutorial coach.
## Defaults to [code]false[/code]. Set to [code]true[/code] on first ROUTE (or
## safety-valve / LOSE) while coaching (see [code]design/gdd/first-time-tutorial.md[/code]
## §3 R6). Missing-key-defaulted in [method from_dict]; no schema bump required —
## old saves correctly default to [code]false[/code] (they have not seen the tutorial).
var tutorial_seen: bool = false

## Coin balance (soft currency). Persisted from [WalletData.coins].
## Added in schema v2 (S3-002 / design/gdd/deck-economy.md §Core Rule 3).
## Clamped to >= 0 in [method from_dict]; upper cap applied by WalletService (S3-004).
var wallet_coins: int = 0

## Gem balance (hard currency). Persisted from [WalletData.gems].
## Added in schema v2 (S3-002 / design/gdd/deck-economy.md §Core Rule 3).
## Clamped to >= 0 in [method from_dict]; upper cap applied by WalletService (S3-004).
var wallet_gems: int = 0

## The UTC day key ([method TimeProvider.utc_day_key]) these daily counters belong to.
## Value 0 means uninitialised (no counters recorded yet). Added in schema v3 (S3-005).
var daily_key: int = 0

## Coins earned from rewarded ads today (resets when [member daily_key] advances).
## Added in schema v3 (S3-005 / design/gdd/deck-economy.md Rule 15 / Formula 8).
var ad_coins_today: int = 0

## Number of rewarded ads watched today (resets when [member daily_key] advances).
## Added in schema v3 (S3-005 / design/gdd/deck-economy.md Rule 15 / Formula 8).
var ads_watched_today: int = 0

## Gems converted to coins today (resets when [member daily_key] advances).
## Added in schema v3 (S3-005 / design/gdd/deck-economy.md Rule 21 / Formula 7).
var gems_converted_today: int = 0

## Level wins recorded today (resets when [member daily_key] advances). Drives the
## once-per-day [code]first_win_bonus[/code] (Formula 1): the bonus applies only when
## this is still 0 at win time. Added in schema v4 (S3-008 / design/gdd/deck-economy.md
## Formula 1, AC-EF01/EF02).
var wins_today: int = 0

## Owned Picker booster count (prototype buff inventory). Consumed for free on use;
## at zero a watch-ad / pay-coins top-up popup is offered. Added in schema v5.
## Clamped to >= 0 in [method from_dict]; seeded once by WalletService (see [member boosters_seeded]).
var boosters_picker: int = 0

## Owned Reshuffle booster count (prototype buff inventory). Added in schema v5.
var boosters_reshuffle: int = 0

## Owned Extra Discard Slot booster count (prototype buff inventory). Added in schema v5.
var boosters_extra_discard: int = 0

## Whether WalletService has seeded the starting booster stock into the counts above.
## False on a fresh/migrated save so first load grants the configured starting stock
## exactly once (distinguishes "new player" from "spent everything to 0"). Added in schema v5.
var boosters_seeded: bool = false

## Whether the player has granted consent for personalized (behavioural) ads. Defaults to
## [code]false[/code] (denied). [b]Protected field[/b] — never served by missing-key-default
## (save-service.md Core Rule 6 / Edge Case 9, ADR-0013 §1). Read only through
## [ComplianceService] (the sole reader); set via [SaveService] consent setters. Added in schema v6.
var consent_personalized_ads: bool = false

## Whether the player has granted consent for analytics data collection. Defaults to
## [code]false[/code] (denied). [b]Protected field[/b] — see [member consent_personalized_ads].
## Added in schema v6.
var consent_analytics: bool = false

## Whether the player has granted consent for IAP data processing. Defaults to
## [code]false[/code] (denied). [b]Protected field[/b] — see [member consent_personalized_ads].
## Added in schema v6.
var consent_iap: bool = false

## Whether the CMP flow has been completed at least once (capture marker). Defaults to
## [code]false[/code] (not yet captured). [b]Protected field[/b] — see
## [member consent_personalized_ads]. Added in schema v6.
var consent_captured: bool = false

## Monotonically increasing consent-version stamp persisted to support a future consent-version
## re-presentation check (comparator deferred to the native-SDK sprint, per ADR-0013 §3).
## A policy change will bump a CURRENT_CONSENT_VERSION constant; when the persisted stamp is
## lower than that value, re-presentation of the consent flow will be triggered. The comparator
## is NOT yet implemented. Defaults to [code]0[/code]. Added in schema v6.
var consent_version: int = 0

## Whether the player owns the Remove-Ads entitlement (purchased or restored). Defaults to
## [code]false[/code] (not owned). [b]Protected field[/b] — never served by missing-key-default
## (save-service.md Core Rule 6 / Edge Case 9, ADR-0014 §3). Read only through
## [EntitlementService] (the sole reader); set via [EntitlementService.grant_remove_ads].
## Added in schema v6 (S4-003) — same migration step as the consent fields (M4-R4: never a
## second [code]if version == 5:[/code] block).
var remove_ads_owned: bool = false


## A fresh save with safe defaults.
static func defaults() -> SaveData:
	return SaveData.new()


## Serializes to a plain [Dictionary] suitable for JSON.
func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"current_level": current_level,
		"age_band": int(age_band),
		"settings": settings.to_dict(),
		"tutorial_seen": tutorial_seen,
		"wallet_coins": wallet_coins,
		"wallet_gems": wallet_gems,
		"daily_key": daily_key,
		"ad_coins_today": ad_coins_today,
		"ads_watched_today": ads_watched_today,
		"gems_converted_today": gems_converted_today,
		"wins_today": wins_today,
		"boosters_picker": boosters_picker,
		"boosters_reshuffle": boosters_reshuffle,
		"boosters_extra_discard": boosters_extra_discard,
		"boosters_seeded": boosters_seeded,
		# Consent fields — protected (ADR-0013 §1, save-service.md Core Rule 6 / EC9).
		# Never served by missing-key-default; always written via the migration step.
		"consent_personalized_ads": consent_personalized_ads,
		"consent_analytics": consent_analytics,
		"consent_iap": consent_iap,
		"consent_captured": consent_captured,
		"consent_version": consent_version,
		# Entitlement field — protected (ADR-0014 §3, S4-003). Conservative: absent/null → not-owned.
		# Read only through EntitlementService.
		"remove_ads_owned": remove_ads_owned,
	}


## Builds a [SaveData] from a parsed dictionary, migrating older schema versions
## and validating / clamping every field. Corrupt or missing fields fall back to
## safe defaults rather than failing — a bad save never crashes the game.
static func from_dict(dict: Dictionary) -> SaveData:
	var from_version: int = int(dict.get("schema_version", 0))
	var migrated: Dictionary = _migrate(dict, from_version)

	var data := SaveData.new()
	data.schema_version = CURRENT_SCHEMA_VERSION
	data.current_level = maxi(1, int(migrated.get("current_level", 1)))
	data.age_band = _parse_age_band(migrated.get("age_band", AgeBand.UNKNOWN))
	data.settings = Settings.from_dict(migrated.get("settings", {}))
	data.tutorial_seen = bool(migrated.get("tutorial_seen", false))
	data.wallet_coins = maxi(0, _safe_int(migrated.get("wallet_coins", 0)))
	data.wallet_gems = maxi(0, _safe_int(migrated.get("wallet_gems", 0)))
	data.daily_key = maxi(0, _safe_int(migrated.get("daily_key", 0)))
	data.ad_coins_today = maxi(0, _safe_int(migrated.get("ad_coins_today", 0)))
	data.ads_watched_today = maxi(0, _safe_int(migrated.get("ads_watched_today", 0)))
	data.gems_converted_today = maxi(0, _safe_int(migrated.get("gems_converted_today", 0)))
	data.wins_today = maxi(0, _safe_int(migrated.get("wins_today", 0)))
	data.boosters_picker = maxi(0, _safe_int(migrated.get("boosters_picker", 0)))
	data.boosters_reshuffle = maxi(0, _safe_int(migrated.get("boosters_reshuffle", 0)))
	data.boosters_extra_discard = maxi(0, _safe_int(migrated.get("boosters_extra_discard", 0)))
	data.boosters_seeded = bool(migrated.get("boosters_seeded", false))
	# Consent fields — protected (ADR-0013 §1). Conservative parsing: null / non-bool /
	# missing -> false (denied). A missing key on downgrade is a compliance defect; the
	# migration step seeds these for every pre-v6 save, and _parse_bool_conservative ensures
	# an absent or corrupt value is never silently treated as granted.
	data.consent_personalized_ads = _parse_bool_conservative(migrated.get("consent_personalized_ads", false))
	data.consent_analytics = _parse_bool_conservative(migrated.get("consent_analytics", false))
	data.consent_iap = _parse_bool_conservative(migrated.get("consent_iap", false))
	data.consent_captured = _parse_bool_conservative(migrated.get("consent_captured", false))
	data.consent_version = maxi(0, _safe_int(migrated.get("consent_version", 0)))
	# Entitlement field — protected (ADR-0014 §3). Conservative parsing: null / non-bool /
	# missing → false (not-owned). A missing key on downgrade must never silently grant
	# Remove-Ads (same protected-field rule as consent — save-service.md Core Rule 6 / EC9).
	data.remove_ads_owned = _parse_bool_conservative(migrated.get("remove_ads_owned", false))
	return data


# Upgrades a raw dict from [param from_version] to the current schema. Each step
# transforms version N into N+1; add a new `if version == N:` block per bump.
# Pre-versioned/unknown saves arrive as version 0 and flow through unchanged into
# the validation in [method from_dict].
static func _migrate(dict: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var version: int = from_version
	# v1 → v2: wallet fields introduced (S3-002, design/gdd/deck-economy.md §Dependencies Save Service).
	if version == 1:
		out["wallet_coins"] = 0
		out["wallet_gems"] = 0
		version = 2
	# v2 → v3: daily cap counters introduced (S3-005, design/gdd/deck-economy.md Rule 15/21).
	if version == 2:
		out["daily_key"] = 0
		out["ad_coins_today"] = 0
		out["ads_watched_today"] = 0
		out["gems_converted_today"] = 0
		version = 3
	# v3 → v4: daily win counter introduced (S3-008, design/gdd/deck-economy.md Formula 1).
	if version == 3:
		out["wins_today"] = 0
		version = 4
	# v4 → v5: prototype buff inventory (owned booster counts + seed flag). Seeded=false so
	# WalletService grants the starting stock once on the next load (existing players included).
	if version == 4:
		out["boosters_picker"] = 0
		out["boosters_reshuffle"] = 0
		out["boosters_extra_discard"] = 0
		out["boosters_seeded"] = false
		version = 5
	# v5 → v6: consent fields (ADR-0013 §1) — protected fields seeded to conservative
	# (denied / not-captured) defaults. S4-003 extends THIS SAME STEP with the Remove-Ads
	# entitlement field as one unconditional line — no second `if version == 5:` block (M4-R4).
	# IDEMPOTENT: idempotency is provided by the VERSION GATE — a v6 dict arrives with
	# from_version == 6 and skips this block entirely; re-running _migrate on a v6 dict
	# executes no step. The unconditional assignments here (matching the v1–v5 ladder style)
	# are strictly safer: a tampered/forward-written version-5 dict carrying a granted consent
	# is conservatively re-seeded to denied, and denying is never a compliance leak.
	if version == 5:
		out["consent_personalized_ads"] = false
		out["consent_analytics"] = false
		out["consent_iap"] = false
		out["consent_captured"] = false
		out["consent_version"] = 0
		out["remove_ads_owned"] = false  # S4-003 (ADR-0014 §3): entitlement in same v6 step (M4-R4).
		version = 6
	return out


# Coerces a Variant to bool conservatively (denied / false). Any value that is not
# an explicit `true` is treated as denied — null, non-bool, non-int, any int other
# than 1. This implements the ADR-0013 §1 protected-field rule: an absent or corrupt
# consent value must NEVER default to a permissive (granted) value.
static func _parse_bool_conservative(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	# JSON may round-trip booleans as int 1/0 depending on the serializer.
	if value is int:
		return value == 1
	return false


# Coerces a Variant to int, treating null and non-numeric values as 0.
# Required because int(null) raises in GDScript — a save with an explicit JSON null
# for a numeric field must not crash (mirrors the null-guard in _parse_age_band).
static func _safe_int(value: Variant) -> int:
	if value == null:
		return 0
	if value is int or value is float:
		return int(value)
	return 0


# Accepts an int / float / enum value; null, non-numeric, or out-of-range -> UNKNOWN.
# Guards the numeric coercion: int(null) and int("x") raise in GDScript, so a save
# with an explicit JSON null age_band must be rejected before coercion (a bad save
# never crashes — see GDD Edge Case 7 / AC AG-06).
static func _parse_age_band(value: Variant) -> AgeBand:
	if not (value is int or value is float):
		return AgeBand.UNKNOWN
	match int(value):
		AgeBand.ADULT:
			return AgeBand.ADULT
		AgeBand.CHILD:
			return AgeBand.CHILD
		_:
			return AgeBand.UNKNOWN
