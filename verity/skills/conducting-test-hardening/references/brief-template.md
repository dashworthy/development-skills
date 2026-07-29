# verity brief — iteration {{N}}

**Run:** {{BASELINE}}...HEAD
**Participating suites:** {{SUITES}}
**Generated:** {{DATE}}

## Summary

| Kind | Count |
|---|---|
| Gap findings | {{GAP_COUNT}} |
| Rework items | {{REWORK_COUNT}} |
| Breakage findings | {{BREAKAGE_COUNT}} |
| Ownership findings | {{OWNERSHIP_COUNT}} |

## Breakage findings

<!-- Any entry here HALTS the run. Never propose a fix. Omit the section when empty. -->
<!-- REPEAT the block below once per breakage finding, in confidence order. -->

### {{ID}} — {{TARGET_FILE}}:{{TARGET_SYMBOL}}

- **Suite:** {{SUITE}}
- **Confidence:** {{CONFIDENCE}}
- **Observation:** {{OBSERVATION}}
- **Expectation:** {{EXPECTATION}}

<!-- /repeat -->

## Ownership findings

<!-- Changed files no suite claims. One bullet each. Omit the section when empty. -->

- `{{PATH}}` — {{NOTE}}

## Gap findings

<!-- REPEAT the block below once per gap finding. The order is TOTAL, so two runs -->
<!-- over the same findings render identically: risk_level (high, medium, low), then -->
<!-- rework before fresh, then target_file ascending, then id ascending. -->
<!-- Omit the section when empty. -->

### {{ID}} — {{TARGET_FILE}}:{{TARGET_SYMBOL}}

- **Suite / track:** {{SUITE}} / {{TRACK}}
- **Risk:** {{RISK_LEVEL}} — {{RISK}}
- **Status:** {{STATUS}}
- **Behavior:** {{BEHAVIOR}}
- **Test intent:** {{TEST_INTENT}}
- **Target test file:** `{{TARGET_TEST_FILE}}`
- **Iteration:** {{ITERATION}}
- **Rework:** {{CARRIED_FROM}} / {{PRIOR_VERDICT}} / {{PRIOR_DEFECT}} @ {{PRIOR_DEFECT_LOCATION}}
- **Prior unevaluated reason:** {{PRIOR_UNEVALUATED_REASON}}
- **Surviving mutant:** {{MUTANT_OPERATOR}} @ {{MUTANT_LINE}}
- **Satisfied by:** {{SATISFIED_BY}}

<!-- /repeat -->

<!-- Omit the Rework, Prior unevaluated reason, Surviving mutant, and Satisfied by lines when -->
<!-- their fields are empty. Prior unevaluated reason applies only when prior_verdict is -->
<!-- "unevaluated" — a carried-forward item whose previous attempt could not be judged. -->
