# GitHub Copilot Instructions for BOSS

These instructions apply to AI-assisted work in this repository. Keep changes small, reviewable, and grounded in the plan documents and tests.

## Repository Context

BOSS translates BuildingSync XML into OpenStudio workflows. Current production behavior is baseline-only: write `baseline/in.osw`, then run that workflow. Preserve that behavior unless the task explicitly changes it.

Important project context lives in:

- `README.md` — setup, CLI use, current baseline workflow, and test commands.
- `docs/scenario_workflow_translation_plan.md` — source of truth for the scenario workflow translation roadmap.
- `spec/files/v2.7.0/` — BuildingSync fixtures used by unit and integration tests.
- `spec/tests/` — existing RSpec coverage patterns.

## Related Repositories and Dependencies

BOSS sits between BuildingSync XML data and OpenStudio workflow execution. Sibling repositories can provide context, but keep implementation changes in BOSS unless the user asks for cross-repo edits.

- `../schema` — BuildingSync schema source and examples. Use it to verify XML structure, element names, `ScenarioType`, `PackageOfMeasures`, `Measure`, `MeasureID`, and schema-version behavior. Do not edit it unless the task asks for schema work.
- `../BuildingSync-gem` — legacy Ruby translator. Use it for workflow concepts and mapping ideas, but verify every behavior against current BOSS dependencies and BuildingSync v2.7 fixtures.
- `../buildingsync-measures-gem` — related BuildingSync/OpenStudio measure work. Use it as reference for measure patterns.
- `../openstudio-standards` — OpenStudio standards logic used by the `openstudio-standards` gem. Do not edit it from BOSS unless the issue is proven upstream and the user asks for that change.
- OpenStudio measure gems declared in `BOSS.gemspec` — `openstudio-common-measures`, `openstudio-ee`, `openstudio-extension`, `openstudio-model-articulation`, and `openstudio-standards`. Verify scenario mapping measure names and arguments against the installed versions used by BOSS.

Rule of thumb: inspect sibling repos freely, but keep BOSS PRs scoped to BOSS files. If a fix belongs upstream, record it as follow-up work.

## Scenario Workflow Translation Work

For work related to BuildingSync `PackageOfMeasures` scenario translation:

1. Read `docs/scenario_workflow_translation_plan.md` before editing code.
2. Check the git state and recent commits to determine which PR steps have already landed.
3. Start with the first roadmap step whose acceptance criteria are not satisfied.
4. Keep changes scoped to that PR step unless a small supporting edit is necessary to make the step coherent.
5. Treat each step's acceptance criteria as done and its avoid list as merge blockers.
6. Preserve existing baseline-only API, CLI behavior, output layout, and integration tests unless the current PR step explicitly changes them.
7. If implementation decisions change the roadmap, update `docs/scenario_workflow_translation_plan.md` in the same PR.

Do not jump ahead because nearby code is tempting. If you find a later concern, record it in the plan or final notes and keep the current PR focused.

## Scope Discipline

Before opening or finalizing a PR:

- Review every changed file and drop exploratory edits that are not needed.
- Keep generated outputs, local run artifacts, and unrelated formatting churn out of the PR.
- Prefer existing project patterns over new abstractions unless the new abstraction clearly removes repeated complexity.
- If a change is documentation-only, say so and do not run unnecessary simulation tests.

## Tests and Verification

Whenever you make code changes, decide whether the change is unit-testable. If it is, add or update focused tests in the same PR.

Use the narrowest useful command first, then broaden as risk increases:

```bash
bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb
bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb
bundle exec rspec spec/tests/integration/write_and_run_osws_spec.rb
bundle exec rake
```

If a test cannot be run locally because dependencies, OpenStudio, weather files, or runtime are unavailable, say so and name the command that should be run later.

## Ruby and Style Checks

For Ruby code changes, run project commands through the bundle when possible:

```bash
bundle exec rubocop <changed-ruby-files>
```

If RuboCop or the bundle is unavailable locally, do not guess. Say what failed and what the reviewer should run after dependencies are available.

## Documentation and Comments

Write for maintainers first.

- Keep comments short and focused on non-obvious behavior.
- Do not narrate what the next line of code already says.
- Put roadmap, rationale, and cross-PR history in `docs/scenario_workflow_translation_plan.md`, not source comments.
- Keep README updates matched to implemented behavior; do not document future result writeback or mapping coverage until it exists.

## Pull Request Description Template

Use a short, plain-language PR body:

```md
## Why do we need this PR
<one or two sentences>

## Core change explanation
<short summary of what changed>

## Which files are affected
- `path/to/file_or_folder`

## What kind of tests are done
- <test command, smoke check, or not run + reason>
```

Optional `Out of scope` or `Follow-up work` sections are useful when they prevent reviewer confusion. Keep long reasoning in the plan doc instead of the PR body.

## CI and Merge Hygiene

- Treat green local tests as necessary but not always sufficient; CI can still catch clean-environment issues.
- If a workflow fails, inspect the failing job logs before suggesting fixes.
- When a scenario workflow PR changes the roadmap or PR boundaries, update `docs/scenario_workflow_translation_plan.md` so future sessions inherit the current truth.