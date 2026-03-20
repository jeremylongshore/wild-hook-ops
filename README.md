# wild-hook-ops

Centralized hook lifecycle management for agent workflows.

Provides registration, priority-ordered execution with timeouts and error isolation, audit logging, and per-handler health metrics for hook/extension points in the wild ecosystem.

**Links:** [GitHub](https://github.com/jeremylongshore/wild-hook-ops)

---

## What It Solves

The wild ecosystem's tools (admin-tools-mcp, rails-safe-introspection-mcp) each reinvented ad-hoc HookEmitter patterns independently. Hook-ops centralises and generalises this into one tested, auditable library.

Think git hooks, but for agent workflows:

> "Before an agent executes a privileged tool, run this validation step."

## Installation

Add to your Gemfile:

```ruby
gem 'wild-hook-ops'
```

## Usage

```ruby
require 'wild_hook_ops'

# Optional: configure before use
WildHookOps.configure do |c|
  c.default_timeout_ms   = 3_000
  c.on_handler_error     = :log_and_continue
  c.enable_audit_logging = true
end

# Create a shared registry
registry = WildHookOps::Registry::HookRegistry.new

# Define hook points
registry.define(
  name:                 'before_tool_call',
  trigger:              :before_tool_call,
  description:          'Fires before any privileged tool call',
  required_permissions: ['tools.execute']
)

# Register handlers
registry.register_handler(
  hook_name: 'before_tool_call',
  callable:  ->(ctx) { audit_log(ctx[:tool]) },
  priority:  10
)

registry.register_handler(
  hook_name:  'before_tool_call',
  callable:   ->(ctx) { validate_permissions(ctx) },
  priority:   50,
  timeout_ms: 1_000
)

# Wire up audit logger and health monitor
audit   = WildHookOps::Audit::Logger.new
monitor = WildHookOps::Health::Monitor.new

runner = WildHookOps::Execution::Runner.new(
  registry:       registry,
  audit_logger:   audit,
  health_monitor: monitor
)

# Execute — returns Array<HookResult>
results = runner.execute('before_tool_call', { tool: 'bash', user: 'alice' })

results.each do |r|
  puts "#{r.handler.id}: #{r.outcome} in #{r.duration_ms}ms"
end

# Query audit trail
audit.trail.for_hook('before_tool_call').each { |e| puts e.to_h }

# Health report
reporter = WildHookOps::Health::Reporter.new(monitor: monitor, registry: registry)
puts reporter.summary.inspect
```

## Key Concepts

| Concept | Description |
|---------|-------------|
| HookDefinition | Declares a named hook point (trigger, permissions, version) |
| HookHandler | A callable registered against a hook (priority, timeout, enabled flag) |
| HookResult | The outcome of executing one handler (:success/:error/:timeout/:skipped) |
| HookEvent | An immutable audit record written for each execution |
| HookRegistry | Central store combining definitions and handlers |
| Runner | Executes handlers in priority order with timeout + error isolation |
| HealthMonitor | Tracks per-handler metrics (call count, error rate, avg duration) |
| AuditTrail | Capped ring buffer of HookEvents, queryable by hook/outcome/time |

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `default_timeout_ms` | 5_000 | Per-handler timeout in milliseconds |
| `max_handlers_per_hook` | 20 | Hard cap on handlers per hook point |
| `enable_audit_logging` | true | Toggle audit trail recording |
| `max_audit_entries` | 10_000 | Ring buffer cap (evicts oldest on overflow) |
| `execution_mode` | :sequential | :sequential or :parallel |
| `on_handler_error` | :log_and_continue | :log_and_continue or :halt |

## Execution Guarantees

- Handlers execute in **ascending priority order** (lower number = earlier)
- Disabled handlers are silently skipped
- `Timeout::Error` is caught per-handler and recorded as `:timeout` — it does not propagate
- `StandardError` and subclasses are isolated per-handler — recorded as `:error`
- With `:halt` mode, execution stops at the first `:error` result
- `SignalException` and `Interrupt` are **not** caught — they propagate normally

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

Intent Solutions Proprietary. See `LICENSE`.
