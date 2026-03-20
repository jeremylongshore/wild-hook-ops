# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Identity

- **Repo**: wild-hook-ops
- **Gem name**: wild-hook-ops
- **Namespace**: WildHookOps
- **Ecosystem**: wild
- **Ecosystem root**: `../CLAUDE.md`
- **Archetype**: C — SDLC Companion
- **Mission**: Centralized hook lifecycle management — registration, execution, auditing, and health monitoring for agent workflow extension points

## What This Repo Does

Hook-ops generalises the ad-hoc HookEmitter patterns found across wild-admin-tools-mcp and wild-rails-safe-introspection-mcp. It provides a single, tested, auditable hook system that any wild-* repo can depend on.

Think git hooks, but for agent workflows. "Before an agent executes a privileged tool, run this validation step."

## Build Commands

```bash
bundle install
bundle exec rspec          # 247 examples, 0 failures
bundle exec rubocop        # 0 offenses
bundle exec rake           # default: runs rspec
```

## Architecture

```
lib/wild_hook_ops.rb                   # Entry point + module-level configure/reset
lib/wild_hook_ops/
  version.rb                           # VERSION constant
  errors.rb                            # All exception classes
  configuration.rb                     # Mutable config with freeze! support
  models/
    hook_definition.rb                 # Immutable hook point descriptor
    hook_handler.rb                    # Registered callable + metadata
    hook_result.rb                     # Per-execution result (outcome, duration, error)
    hook_event.rb                      # Audit event record
  registry/
    definition_store.rb                # Thread-safe store for HookDefinitions
    handler_store.rb                   # Thread-safe store for HookHandlers
    hook_registry.rb                   # Unified API combining both stores
  execution/
    timeout_guard.rb                   # Enforce per-handler timeout using Timeout stdlib
    error_isolator.rb                  # Catch StandardError without propagating
    runner.rb                          # Execute hooks: priority sort, timeout, isolation
  lifecycle/
    version_tracker.rb                 # Track version history for definitions
    manager.rb                         # Enable/disable/deprecate hooks and handlers
  health/
    monitor.rb                         # Per-handler metrics (calls, errors, timeouts, duration)
    reporter.rb                        # Generate health summary/detail reports
  audit/
    trail.rb                           # Ring-buffer store for HookEvents, queryable
    logger.rb                          # Record HookResults as HookEvents into the trail
```

## Key Conventions

- No external dependencies beyond Ruby stdlib (Timeout)
- All stores are thread-safe with Mutex
- Audit trail is a capped ring buffer (evicts oldest on overflow)
- Handlers execute in ascending priority order (lower = first)
- Timeout via `Timeout.timeout` — records `:timeout` outcome, does not propagate
- StandardError isolation — records `:error` outcome, halts or continues per config
- `WildHookOps.reset_configuration!` in every spec `before` block
- `spec/support/hook_fixtures.rb` provides `HookFixtures` mixin for all tests

## Configuration

```ruby
WildHookOps.configure do |c|
  c.default_timeout_ms    = 5_000     # Integer, positive
  c.max_handlers_per_hook = 20        # Integer, positive
  c.enable_audit_logging  = true      # Boolean
  c.max_audit_entries     = 10_000    # Integer, positive (ring buffer cap)
  c.execution_mode        = :sequential  # :sequential | :parallel (parallel not yet implemented)
  c.on_handler_error      = :log_and_continue  # :log_and_continue | :halt
  c.freeze!               # Optional: lock config after initialization
end
```

## Ecosystem Role

Wild repos that need hook points (e.g. `before_tool_call`, `on_capability_check`) should depend on this gem. Emit hooks via `Runner#execute`; register handlers via `HookRegistry#register_handler`.

## Working Here

1. Read `../CLAUDE.md` (ecosystem root) before starting
2. Never touch `main` directly — work on feature branches
3. Auto-commit, auto-push, auto-PR on feature branches
4. All changes require passing `rspec` and `rubocop` before commit
5. Keep `spec/adversarial/` growing — add adversarial cases for any new edge you discover
