# guardtower brief — {{RUN_ID}}

**PR:** {{PR_REFERENCE}}
**Base → head:** {{BASE_SHA}} → {{HEAD_SHA}}
**Lenses run:** {{LENSES_RUN}}
**Lenses skipped:** {{LENSES_SKIPPED}}
**Threshold:** {{THRESHOLD}}
**Generated:** {{DATE}}

## Summary

| Kind | Count |
|---|---|
| Passed the gate | {{PASSED_COUNT}} |
| Dropped on evidence | {{DROPPED_COUNT}} |
| Discarded by gate | {{DISCARDED_COUNT}} |

## Findings

<!-- REPEAT the block below once per finding that passed the gate. -->
<!-- Order is the scoring rubric's total order: composite descending, then value descending, -->
<!-- then target_file ascending, then id ascending — so two runs over the same findings render -->
<!-- an identical brief. Omit this whole section when PASSED_COUNT is 0. -->

### {{ID}} — {{TARGET_FILE}}:{{TARGET_LINE}}

- **Lens:** {{LENS}}
- **Composite:** {{COMPOSITE}} (value {{VALUE}} / urgency {{URGENCY}})
- **In diff:** {{IN_DIFF}}
- **Claim:** {{CLAIM}}
- **Rationale:** {{RATIONALE}}
- **Proposal:** {{PROPOSAL}}
- **Kind:** {{KIND}}
- **Tier:** {{TIER}}
- **Existing solution:** {{EXISTING_SOLUTION}}
- **Adoption cost:** {{ADOPTION_COST}}

<!-- /repeat -->

<!-- The Kind, Tier, and Existing solution lines exist only on a reuse finding — omit all three -->
<!-- for every finding from another lens. Adoption cost exists only on a reuse finding whose tier -->
<!-- is 2 — omit it for reuse findings at tier 1, and for every non-reuse finding regardless of -->
<!-- tier. -->
