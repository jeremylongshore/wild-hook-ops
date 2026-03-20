# Changelog

## [0.1.0] - 2026-03-20

### Added

- `WildHookOps::Models::HookDefinition` — immutable hook point descriptor with trigger, permissions, version, deprecated flag
- `WildHookOps::Models::HookHandler` — registered callable with priority, timeout, enable/disable
- `WildHookOps::Models::HookResult` — per-execution result with outcome, duration, error, return_value
- `WildHookOps::Models::HookEvent` — immutable audit record with context_summary and truncation
- `WildHookOps::Registry::DefinitionStore` — thread-safe store for HookDefinitions
- `WildHookOps::Registry::HandlerStore` — thread-safe store for HookHandlers with per-hook limit enforcement
- `WildHookOps::Registry::HookRegistry` — unified API combining both stores
- `WildHookOps::Execution::TimeoutGuard` — per-handler timeout via Timeout stdlib
- `WildHookOps::Execution::ErrorIsolator` — StandardError isolation without propagation
- `WildHookOps::Execution::Runner` — priority-ordered execution with timeout/isolation, audit, health recording
- `WildHookOps::Lifecycle::VersionTracker` — version history for hook definitions
- `WildHookOps::Lifecycle::Manager` — enable/disable/deprecate hooks and handlers
- `WildHookOps::Health::Monitor` — per-handler metrics: call count, success/error/timeout counts, avg duration, error rate
- `WildHookOps::Health::Reporter` — summary and detailed health reports with stale handler detection
- `WildHookOps::Audit::Trail` — capped ring buffer for HookEvents, queryable by hook/outcome/handler/time range
- `WildHookOps::Audit::Logger` — records HookResults as HookEvents with context summarisation
- `WildHookOps::Configuration` — full configuration with freeze! support
- 247 tests (unit, integration, adversarial) — 0 failures
- 0 RuboCop offenses
