# Story 19.13: Delete Legacy Code

Status: ready-for-dev

## Story

As a developer,
I want replaced code removed,
so that there's no confusion about which execution path is active.

## Acceptance Criteria

1. Delete `app/services/container_strategies/tool_execution_strategy.rb`
2. Delete `app/services/container_strategies/code_climate_strategy.rb`
3. Delete `app/services/internal_tools/code_climate.rb`
4. All references to old strategy classes updated throughout codebase
5. All tests referencing old strategies updated to use new strategies
6. `Tool#execute` does not reference `ToolExecutionStrategy` or `CodeClimateStrategy`
7. No broken requires or autoload references to deleted files
8. All existing tests pass

## Tasks / Subtasks

- [ ] Task 1: Delete files (AC: #1-#3)
  - [ ] Delete `app/services/container_strategies/tool_execution_strategy.rb`
  - [ ] Delete `app/services/container_strategies/code_climate_strategy.rb`
  - [ ] Delete `app/services/internal_tools/code_climate.rb`
- [ ] Task 2: Update references (AC: #4, #6, #7)
  - [ ] Search codebase for `ToolExecutionStrategy` — update all references to `CustomToolStrategy`
  - [ ] Search codebase for `CodeClimateStrategy` — remove references (replaced by DSL in InternalToolStrategy)
  - [ ] Search codebase for `InternalTools::CodeClimate` — remove references (replaced by DSL)
  - [ ] Check `container_service.rb` — strategy resolution must use new classes
  - [ ] Check `temporal_service.rb` — workflow references
  - [ ] Check initializers for autoload references
- [ ] Task 3: Update tests (AC: #5, #8)
  - [ ] Delete or rewrite tests for `ToolExecutionStrategy`
  - [ ] Delete or rewrite tests for `CodeClimateStrategy`
  - [ ] Delete or rewrite tests for `InternalTools::CodeClimate`
  - [ ] Verify test suite passes: `make test`
- [ ] Task 4: Verify clean state (AC: #7, #8)
  - [ ] Run full test suite
  - [ ] Run `rails runner 'ToolExecutionStrategy'` — should raise NameError
  - [ ] Run `rails runner 'ContainerStrategies::CodeClimateStrategy'` — should raise NameError
  - [ ] Run `rails runner 'InternalTools::CodeClimate'` — should raise NameError

## Dev Notes

- This story must be done LAST — after all new strategies are implemented and verified
- Dependency: all of 19.1-19.12 must be complete and tested
- Do a final grep for deleted class names to ensure nothing references them
- `InternalToolExecutor` stays — it routes app-mode tools
- `InternalTools::Base` stays — base class for app-mode handlers

### Project Structure Notes

- Delete: `app/services/container_strategies/tool_execution_strategy.rb`
- Delete: `app/services/container_strategies/code_climate_strategy.rb`
- Delete: `app/services/internal_tools/code_climate.rb`
- Delete corresponding test files

### References

- [Source: ai/tool-execution-framework.md#8] — what gets deleted
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.13] — acceptance criteria
