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
<!-- Order is the scoring rubric's total order, and it is that document's wording verbatim: -->
<!-- `composite` descending, then `value` descending, then `target_file` ascending, then `id` ascending -->
<!-- — so two runs over the same findings render an identical brief. -->
<!-- Omit this whole section when PASSED_COUNT is 0. -->

### {{ID}} — {{TARGET_FILE}}:{{TARGET_LINE}}

- **Lens:** {{LENS}}
- **Composite:** {{COMPOSITE}} (value {{VALUE}} / urgency {{URGENCY}})
- **In diff:** {{IN_DIFF}}
- **Also at:** {{ALSO_AT}}
- **Corroborated by:** {{CORROBORATED_BY}}
- **Claim:** {{CLAIM}}
- **Rationale:** {{RATIONALE}}
- **Proposal:** {{PROPOSAL}}
- **Kind:** {{KIND}}
- **Tier:** {{TIER}}
- **Existing solution:** {{EXISTING_SOLUTION}}
- **Adoption cost:** {{ADOPTION_COST}}

<!-- /repeat -->

<!-- The Also at line exists only on a finding whose also_at array is non-empty — omit the line -->
<!-- when the finding sits at a single location, and render every other location when it does -->
<!-- not, comma-joined. An extract finding usually spans several files and TARGET_FILE names -->
<!-- only the clearest of them, so dropping ALSO_AT reports one occurrence of a problem found in -->
<!-- five. -->

<!-- The Corroborated by line exists only on a finding whose corroborated_by array is non-empty, -->
<!-- and renders one "<lens> (<id>): <claim>" per entry, comma-joined. Those are the other lenses -->
<!-- that independently found this same defect at the same evidence span; the arbitrator folded -->
<!-- them into this entry instead of ranking one defect twice. Rendering it is the whole point of -->
<!-- deduping rather than discarding: a defect three lenses found independently is stronger -->
<!-- evidence than one lens's opinion, and a brief that drops the line reports the weaker claim -->
<!-- while looking identical to a finding nothing corroborates. -->

<!-- The Kind line exists on every reuse finding, whatever its kind — omit it only for a finding -->
<!-- from another lens. Tier and Existing solution exist on a reuse finding whose kind is -->
<!-- reimplements, duplicates or diverges, and NOT on one whose kind is extract, which cites no -->
<!-- existing solution by definition — omit both there and for every finding from another lens. -->
<!-- Adoption cost exists only on a reuse finding at tier 2 — omit it at tier 1, on every extract -->
<!-- finding, and for every non-reuse finding regardless of tier. -->
