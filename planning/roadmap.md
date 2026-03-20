# Roadmap — wild-hook-ops

## v0.1.0 — Foundation (Done)

Core hook lifecycle management: registration, execution, audit, health, lifecycle.

- Full model layer (HookDefinition, HookHandler, HookResult, HookEvent)
- Thread-safe registry (DefinitionStore, HandlerStore, HookRegistry)
- Execution engine with timeout and error isolation
- Audit trail (ring buffer, queryable)
- Health monitoring (per-handler metrics, reporter)
- Lifecycle management (enable/disable/deprecate, version tracking)
- 247 tests — 0 failures, 0 RuboCop offenses
- Full documentation pack (blueprint, architecture decisions, config ref, operator guide, safety model)

## v0.2.0 — Ecosystem Integration (Planned)

- Extract and migrate HookEmitter from wild-admin-tools-mcp
- Extract and migrate HookEmitter from wild-rails-safe-introspection-mcp
- Add shared hook definitions for standard wild trigger points
- Published to private gem registry or GitHub Packages

## v0.3.0 — Parallel Execution (Planned)

- Implement `:parallel` execution_mode in Runner
- Thread-per-handler with result collection and timeout semantics
- Benchmark against sequential baseline

## v0.4.0 — Persistence Bridge (Planned)

- Optional adapter interface for draining audit trail to external store
- Example adapter for wild-session-telemetry
