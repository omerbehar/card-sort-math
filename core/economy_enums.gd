class_name EconomyEnums
extends RefCounted
## Shared enumerations for the Deck Economy layer.
##
## These enums provide type-safety for callers (WalletService, HUD,
## WalletData). [EconomyEvent] payload fields carry plain [int] values that
## index into these enums — keeping [EconomyEvent] a leaf with no dependency
## on this file at the type level.
##
## Source: design/gdd/deck-economy.md §Core Rules, §Economy Events;
##         design/registry/entities.yaml (EarnSource, EconomyEvent entries).
## Ratified by: ADR-0008.


## The two wallet currencies. Coins are soft (earned through play); Gems are
## hard (acquired via IAP or milestone gifts). Never fungible upward
## (Coins → Gems is forbidden by Core Rule 1).
enum Currency {
	COINS, ## Soft currency; faucets: level wins, daily challenges, rewarded ads, streaks, milestones.
	GEMS,  ## Hard currency; faucets: IAP purchases, milestone gifts.
}


## Provenance of a coin or gem credit. Used as the [code]source[/code] field
## on [EconomyEvent.CURRENCY_EARNED]. Canonical list from the entity registry.
## [br][br]
## [b]GEM_CONVERT[/b]: gem-to-coin conversion earn (AC-GC01).
## [b]IAP[/b]: verified IAP purchase credited via IAPService.earn().
## [b]MILESTONE_GIFT[/b]: one-time coin/gem package at a level milestone.
## [b]REWARDED_AD[/b]: completed rewarded-ad earn (gated by ComplianceService.is_restricted()).
enum EarnSource {
	LEVEL_WIN,       ## Coins from winning a level (star-weighted, Formula 1/1b).
	DAILY_CHALLENGE, ## Coins from completing the daily challenge (Rule 14).
	REWARDED_AD,     ## Coins from a completed rewarded ad (Rule 15; compliance-gated).
	IAP,             ## Gems credited after a verified IAP purchase (M4 IAPService).
	MILESTONE_GIFT,  ## Coins or gems awarded at a level-completion milestone (Rule 17/18).
	GEM_CONVERT,     ## Coins earned by converting gems at the penalised rate (Rule 21, Formula 7).
}


## The three consumable boosters. Undo was removed from the design (2026-06-12);
## Hint was replaced by Picker (2026-06-13). The Picker plays a covered (lower-layer)
## card the player chooses — it never reveals an arithmetic answer, so the
## no-arithmetic-solving pillar holds. See design/gdd/deck-economy.md.
enum BoosterType {
	PICKER,        ## Plays a covered (lower-layer) card the player chooses (bypasses coverage; no answer reveal).
	RESHUFFLE,     ## Re-generates the floor layout while preserving cards and queue (Rule 10).
	EXTRA_DISCARD, ## Adds one temporary discard slot for the current level (Rule 11).
}


## Reason codes for booster precondition failures, IAP blocks, and earn-cap events.
## Carried in the [code]reason[/code] field of BOOSTER_PRECONDITION_FAILED,
## BOOSTER_PURCHASE_FAILED, IAP_BLOCKED, and EARN_CAP_REACHED events.
## [br][br]
## There is no NO_HISTORY reason — that was Undo-only and Undo has been removed.
## [br][br]
## The four [code]*_CAP[/code] / [code]WALLET_FULL[/code] reasons let the HUD tell
## the EARN_CAP_REACHED variants apart (e.g. "watched max ads today" vs "daily coin
## cap reached" vs "wallet full") — all three otherwise share source REWARDED_AD.
enum FailReason {
	INVALID_TARGET,       ## Picker: the chosen card is already gone or the board is over.
	DISCARD_FULL,         ## Extra Discard precondition: discard row is already full (EC-06, AC-E05).
	AT_MAX,               ## Extra Discard precondition: already at MAX_DISCARD_SLOTS (EC-07, AC-E04).
	WON_BOARD,            ## Reshuffle precondition: board is already in WIN state (EC-15, AC-R05).
	COMPLIANCE_RESTRICTED, ## IAP blocked because ComplianceService.is_restricted() is true (AC-CL01).
	AD_COUNT_CAP,         ## Rewarded-ad earn blocked: max_ads_per_day reached (Formula 8, AC-C01).
	DAILY_COIN_CAP,       ## Rewarded-ad earn blocked: daily_coins_cap reached (Rule 15, AC-C01).
	GEM_CONVERT_CAP,      ## Gem→coin conversion blocked: daily_gem_convert_cap reached (Rule 21, AC-GC02).
	WALLET_FULL,          ## Earn blocked: balance already at the per-currency hard cap (coins_max/gems_max).
}
