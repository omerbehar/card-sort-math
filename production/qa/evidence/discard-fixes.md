# QA Evidence — Discard buff + discard-row fixes

> **Date**: 2026-06-14
> **Reports addressed** (from player screenshots):
> 1. Extra Discard booster doesn't respond when the discard row is full (5/5).
> 2. Adding a deck should auto-assign matching discarded cards onto it.
> 3. Adding a discard slot should re-home the cards already in the row (they were
>    left sitting between the re-centred slots).
> **Implements**: design/gdd/deck-economy.md (Core Rule 11, EC-06/AC-E05 revised), ADR-0010 (2026-06-14 amendment)

## Fixes

1. **Extra Discard now works when full.** `WalletService._extra_discard_allowed`
   dropped the "purchase-ahead-only" `DISCARD_FULL` precondition; only the absolute
   slot cap (`AT_MAX`) gates it now. At 5/5 the booster adds a 6th slot (rescue).
2. **Deck unlock auto-assigns discards** — already implemented in the model
   (`BoardModel.unlock_stack` → `_pull_matching`) and replayed by the view
   (`Main._perform_unlock` → PULL events). Now covered by an end-to-end test that
   drives the real unlock prompt and asserts the discarded card moves onto the deck.
3. **Discard cards re-home on grow.** `DiscardRow.set_slot_count` re-centres the
   slot *frames*, but the card nodes were not moved. `Main._grow_discard_view` now
   calls `_reposition_discard_cards`, sliding each card to its slot's new centred
   global position. Centralised across all three grow paths (`expand_discard`,
   `buy_extra_discard`, `extra_discard_from_stock`).

## Automated test evidence (all green — full suite 514 cases, 0 failures)

- `tests/test_wallet_service.gd::test_use_extra_discard_when_row_full_now_expands_and_deducts`
  — at 5/5 the booster expands 5→6 and deducts; no `DISCARD_FULL` event (updated from
  the old "blocked" assertion).
- `tests/integration/discard_fixes_test.gd` (drives `scenes/main/main.tscn`):
  - `test_extra_discard_works_when_row_is_full` — fill 5/5, press the booster, model
    and view both grow to 6, one stock consumed.
  - `test_growing_the_row_repositions_existing_discard_cards` — after a 5→7 grow,
    every occupied discard card sits on its re-centred slot (within 4px; a
    non-repositioned card would be ~26px off).
  - `test_unlocking_a_deck_pulls_matching_discarded_cards_onto_it` — discard a 9 while
    its deck is locked, unlock the deck (draws 9): the card leaves the discard and
    lands on the deck.
- Existing model coverage retained: `tests/test_board_model.gd::test_unlock_stack_draws_next_target_and_pulls_from_discard`.

## Screenshot evidence

- `discard-expand-reposition.png` — captured via `tools/screenshot_discard_expand.gd`
  (`xvfb-run … opengl3 gl_compatibility`). The discard row expanded 5→7; the cards
  already in the row sit centred on their slots (not between slots).

## Note — card overlap on the table

The overlap between floor cards is the intended **coverage mechanic** (higher-layer
cards partly cover lower ones; you clear exposed cards to reveal them). It comes from
the fixed authored layouts (`core/layouts.gd`) and is unchanged by these fixes or by
the operation-worlds work. No regression; flagged here for the record.
