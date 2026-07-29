# Stack markers — fallback candidates

This is the weakest of the four evidence sources `detecting-the-stack` consults, and the
only file in this plugin permitted to name specific tools, languages, or runners — the
skill body stays ecosystem-neutral so verity itself never hard-codes a stack. Consult this
table **only after** declared manifest scripts, CI workflow definitions, and runner
configuration files have all been checked for a given suite and yielded nothing. Every
command below is a **candidate**, not a fact: it exists to give the user something
concrete to confirm or correct, not to be trusted unverified. Whatever this table proposes
stays unverified until the conductor's preflight actually runs it — see Preflight step 5 in
`conducting-test-hardening`'s `SKILL.md` — and when detection can't infer a command at all,
that same preflight is where the conductor asks the user directly rather than guessing.

A marker file's presence only proposes a suite. It does not excuse skipping the stronger
sources first — a project with a manifest script for `test` but no coverage script still
owes that manifest a look before this table is opened for the coverage command alone.

| Marker file | Ecosystem / runner | Candidate `test` | Candidate `coverage` (+ report flag) | Candidate `mutation` | Candidate BDD (`gherkin`) | Likely report format |
|---|---|---|---|---|---|---|
| `composer.json` + `phpunit.xml`(`.dist`) | PHP / PHPUnit | `vendor/bin/phpunit` | `vendor/bin/phpunit --coverage-clover=build/coverage.xml` — the `--coverage-clover=<path>` flag is what writes the machine-readable report; without it PHPUnit only prints a summary | `vendor/bin/infection --logger-json=build/infection.json` (requires an `infection.json.dist`) | `vendor/bin/behat` — only when `features/*.feature` and a `behat.yml` exist | Coverage: clover. Mutation: infection-json |
| `package.json` + `jest.config.*` | JavaScript/TypeScript / Jest | `npx jest` | `npx jest --coverage --coverageReporters=json-summary` — the default `--coverage` run prints a text summary only; `--coverageReporters` must include a machine-readable one | `npx stryker run --reporters json` (Stryker Mutator, needs `stryker.conf.*`) | `npx cucumber-js` — only when `*.feature` files and step definitions exist | Coverage: lcov or json-summary (`coverage/`). Mutation: stryker mutation-report json |
| `package.json` + `vitest.config.*` | JavaScript/TypeScript / Vitest | `npx vitest run` | `npx vitest run --coverage --coverage.reporter=json-summary` — the reporter flag is required; a bare `--coverage` run may only print to the terminal | `npx stryker run --reporters json` (Stryker Mutator has a Vitest runner) | `npx cucumber-js` — only when `*.feature` files exist | Coverage: lcov or json-summary. Mutation: stryker mutation-report json |
| `pyproject.toml` (pytest config) | Python / pytest | `pytest` | `pytest --cov=. --cov-report=xml` — `--cov-report=xml` is what writes `coverage.xml`; `--cov` alone only prints a terminal table | `mutmut run` then `mutmut junitxml > build/mutmut.xml` (mutmut has no config-file default report; the second command is what makes it machine-readable) | `behave` or `pytest-bdd` — only when `features/*.feature` and step files exist | Coverage: cobertura (`coverage.xml`). Mutation: junit-xml (via `mutmut junitxml`) |
| `tox.ini` | Python / tox-orchestrated | `tox` | `tox -e coverage` if such an env is declared, otherwise `coverage run -m pytest && coverage xml` — the `coverage xml` step is what emits a machine-readable report; `tox` alone typically just prints pass/fail | same as `pyproject.toml` row above | same as `pyproject.toml` row above | Coverage: cobertura |
| `Gemfile` (rspec) | Ruby / RSpec | `bundle exec rspec` | `bundle exec rspec` with SimpleCov configured to use a machine-readable formatter (e.g. `simplecov-cobertura` or `SimpleCov::Formatter::JSONFormatter`) — SimpleCov's default HTML formatter is not machine-readable; the formatter line is the "report flag" here | `bundle exec mutant run --reporter json` (requires the `mutant` gem) | `bundle exec cucumber` — only when `features/*.feature` exist | Coverage: cobertura or simplecov-json. Mutation: mutant json |
| `go.mod` | Go | `go test ./...` | `go test ./... -coverprofile=coverage.out` then convert, e.g. `gocov convert coverage.out \| gocov-xml > build/coverage.xml` — the raw `-coverprofile` output is not machine-readable on its own; the conversion step is what produces a parseable report | `gremlins run --output build/mutation.json` (or `go-mutesting`) | `godog` — only when `features/*.feature` exist | Coverage: cobertura (post-conversion). Mutation: gremlins json |
| `Cargo.toml` | Rust | `cargo test` | `cargo tarpaulin --out Xml` — the `--out Xml` flag is what writes `cobertura.xml`; a bare `cargo test` run has no coverage output at all | `cargo mutants --json` (writes to `mutants.out/`) | via a Cucumber-for-Rust dependency — only when `*.feature` files exist | Coverage: cobertura (tarpaulin). Mutation: cargo-mutants json |
| `pom.xml` | Java/Kotlin / Maven | `mvn test` | `mvn test jacoco:report` — the `jacoco:report` goal is what writes `target/site/jacoco/jacoco.xml`; `mvn test` alone produces no coverage artifact | `mvn org.pitest:pitest-maven:mutationCoverage` (PIT, requires the plugin declared in `pom.xml`) | `mvn test` with a Cucumber-JVM dependency — only when `src/test/resources/**/*.feature` exist | Coverage: jacoco. Mutation: pitest xml |
| `build.gradle`(`.kts`) | Java/Kotlin / Gradle | `./gradlew test` | `./gradlew jacocoTestReport` — the dedicated task is what writes `build/reports/jacoco/test/jacocoTestReport.xml`; `./gradlew test` alone produces no coverage artifact | `./gradlew pitest` (requires the `pitest-gradle` plugin) | `./gradlew test` with a Cucumber-JVM dependency — only when `**/*.feature` exist | Coverage: jacoco. Mutation: pitest xml |
| `*.csproj` | .NET | `dotnet test` | `dotnet test --collect:"XPlat Code Coverage"` — the `--collect` flag is what writes `**/TestResults/**/coverage.cobertura.xml`; a bare `dotnet test` produces no coverage artifact | `dotnet stryker` (Stryker.NET, writes `StrykerOutput/**/reports/mutation-report.json`) | `dotnet test` with a SpecFlow project — only when `*.feature` files exist | Coverage: cobertura. Mutation: stryker mutation-report json |

## Candidate `test_filter` — required, and the easiest field to leave empty

`test_filter` runs a **single named test in isolation**, and it is not optional: it is what
`verifying-test-integrity` uses for both of its mandatory mechanical checks. Without it, order
dependence cannot be checked at all — a test that only passes because an earlier test left state
behind reads exactly like a clean one, and no amount of inspection separates them. A suite derived
from this table with `test_filter` left blank is a suite whose tests are verified more weakly than
any other, permanently and silently. Propose one from this table rather than leaving the field out.

Each takes a `{filter}` placeholder, matching the column the row's runner appears in above:

| Runner | Candidate `test_filter` |
|---|---|
| PHPUnit | `vendor/bin/phpunit --filter '{filter}'` |
| Jest | `npx jest -t '{filter}'` |
| Vitest | `npx vitest run -t '{filter}'` |
| pytest | `pytest -k '{filter}'` |
| tox | `tox -- -k '{filter}'` (passes through to the underlying pytest) |
| RSpec | `bundle exec rspec -e '{filter}'` |
| Go | `go test ./... -run '{filter}'` |
| Rust | `cargo test '{filter}'` |
| Maven | `mvn test -Dtest='{filter}'` |
| Gradle | `./gradlew test --tests '{filter}'` |
| .NET | `dotnet test --filter 'FullyQualifiedName~{filter}'` |

The matching semantics differ per runner and that matters when a filter silently selects nothing:
`-k` takes a substring expression, `-run` and `--tests` take patterns, and `--filter` takes .NET's
own expression syntax. A filter that matches zero tests exits successfully on most runners, which
is indistinguishable from a passing run — so whoever applies this must confirm the filtered run
actually named the test, exactly as `verifying-test-integrity` requires.

Notes for whoever applies this table:

- A marker file establishes an ecosystem, not a suite boundary by itself. If the stronger
  evidence sources already located this suite's runner, use this table only to fill in
  whichever specific field (usually `coverage` or `mutation`) they left unanswered.
- Where a row lists two candidate reporters or config styles, prefer whichever one other
  files in the same directory tree already reference (a lockfile, an existing CI step, an
  ignored report path in version control) over guessing.
- Every command in this table is unverified until the conductor's preflight actually runs
  it. Present it to the user as "candidate, needs confirmation," never as a fact already
  established.
