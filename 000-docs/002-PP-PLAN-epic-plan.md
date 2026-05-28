# 002 — Epic Plan: wild-hook-ops

## Epic Overview

| Epic | Title | Status |
|------|-------|--------|
| E1 | Foundation: errors, configuration, version | Done |
| E2 | Models: HookDefinition, HookHandler, HookResult, HookEvent | Done |
| E3 | Registry: DefinitionStore, HandlerStore, HookRegistry | Done |
| E4 | Execution: TimeoutGuard, ErrorIsolator, Runner | Done |
| E5 | Lifecycle: VersionTracker, Manager | Done |
| E6 | Health: Monitor, Reporter | Done |
| E7 | Audit: Trail, Logger | Done |
| E8 | Test coverage: unit, integration, adversarial | Done |
| E9 | Docs and gemspec | Done |
| E10 | CI, packaging, ecosystem integration | Pending |

## Epic Details

### E1 — Foundation
- `version.rb`: VERSION constant
- `errors.rb`: Error hierarchy (HookNotFoundError, DuplicateHookError, HandlerLimitExceededError, ConfigurationFrozenError, InvalidConfigurationError, InvalidHandlerError)
- `configuration.rb`: All config keys with validation and freeze!

### E2 — Models
- `HookDefinition`: name, trigger, description, required_permissions, version, deprecated
- `HookHandler`: hook_name, callable, priority, timeout_ms, enabled, metadata, id
- `HookResult`: handler, outcome, duration_ms, error, return_value, executed_at
- `HookEvent`: hook_name, handler_id, outcome, duration_ms, timestamp, context_summary, error_message

### E3 — Registry
- `DefinitionStore`: register, fetch, find, registered?, all, deprecated, active, by_trigger, count, clear!
- `HandlerStore`: register (with limit), for_hook, enabled_for_hook, find_by_id, all, count_for, total_count, hook_names, clear!
- `HookRegistry`: define, register_handler, handlers_for (sorted), definition_for, hook_defined?, all_definitions, all_handlers, clear!

### E4 — Execution
- `TimeoutGuard`: wraps block with Timeout.timeout, returns [:ok/:timeout, value, duration_ms]
- `ErrorIsolator`: wraps block in rescue StandardError, returns [:ok/:error, value/exception]
- `Runner`: execute(hook_name, context) — sort by priority, wrap each handler, return Array<HookResult>

### E5 — Lifecycle
- `VersionTracker`: record, history_for, current_version, all_history, clear!
- `Manager`: enable_handler, disable_handler, enable_all_for, disable_all_for, deprecate_hook, update_version

### E6 — Health
- `Monitor::Metrics` Struct with avg_duration_ms, error_rate, success_rate, to_h
- `Monitor`: record, metrics_for, all_metrics, slow_handlers, failing_handlers, stale_handlers, clear!
- `Reporter`: summary (includes stale), detailed, for_handler

### E7 — Audit
- `Trail`: append (ring buffer), all, count, for_hook, by_outcome, for_handler, in_range, clear!
- `Logger`: record (respects enable_audit_logging), trail accessor

### E8 — Tests
- Unit specs for every class
- Integration spec: full lifecycle end-to-end
- Adversarial spec: error isolation, timeouts, halt mode, ring buffer pressure, concurrency, edge values

### E9 — Docs
- CLAUDE.md with architecture, conventions, workflow
- README.md with usage examples and concept table
- CHANGELOG.md
- 000-docs/ pack (this file)

### E10 — CI and Packaging (Pending)
- GitHub Actions CI (Ruby 3.2, 3.3)
- Gemini code review workflow
- Gemspec finalized for rubygems.org release
- Ecosystem integration docs for wild-admin-tools-mcp
