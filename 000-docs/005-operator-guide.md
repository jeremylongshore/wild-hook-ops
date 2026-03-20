# 005 — Operator Guide: wild-hook-ops

## Integration Pattern

Hook-ops is designed to be used as a shared dependency. The typical integration pattern in a wild-* tool:

1. Create a single `HookRegistry` at boot time (application-scoped or request-scoped)
2. Define hook points relevant to the tool
3. Allow external callers to register handlers
4. Create a `Runner` wired to `Audit::Logger` and `Health::Monitor`
5. Call `runner.execute` at each hook point
6. Expose the `Reporter` for observability

## Boot-Time Setup

```ruby
# config/hooks.rb or initializer

WildHookOps.configure do |c|
  c.default_timeout_ms   = 3_000
  c.on_handler_error     = :log_and_continue
  c.enable_audit_logging = true
  c.max_audit_entries    = 5_000
  c.freeze!
end

HOOK_REGISTRY = WildHookOps::Registry::HookRegistry.new

HOOK_REGISTRY.define(name: 'before_tool_call',    trigger: :before_tool_call)
HOOK_REGISTRY.define(name: 'after_tool_call',     trigger: :after_tool_call)
HOOK_REGISTRY.define(name: 'on_capability_check', trigger: :on_capability_check)
HOOK_REGISTRY.define(name: 'on_error',            trigger: :on_error)

HOOK_AUDIT   = WildHookOps::Audit::Logger.new
HOOK_MONITOR = WildHookOps::Health::Monitor.new

HOOK_RUNNER = WildHookOps::Execution::Runner.new(
  registry:       HOOK_REGISTRY,
  audit_logger:   HOOK_AUDIT,
  health_monitor: HOOK_MONITOR
)
```

## Registering Handlers

```ruby
# Register at boot or dynamically
HOOK_REGISTRY.register_handler(
  hook_name: 'before_tool_call',
  callable:  MyAuditService.method(:before_tool),
  priority:  10,
  timeout_ms: 500,
  metadata:  { source: 'my_audit_service' }
)
```

## Executing Hooks

```ruby
# At the tool call boundary
results = HOOK_RUNNER.execute('before_tool_call', {
  tool:    'bash',
  user:    current_user.id,
  command: params[:command]
})

# Check for blocking failures
if results.any?(&:error?) && config.on_handler_error == :halt
  raise 'Hook chain halted — aborting tool call'
end
```

## Lifecycle Operations

```ruby
lifecycle = WildHookOps::Lifecycle::Manager.new(registry: HOOK_REGISTRY)

# Disable a specific handler temporarily
lifecycle.disable_handler(handler.id)

# Re-enable
lifecycle.enable_handler(handler.id)

# Disable all handlers for a hook (e.g. for maintenance)
lifecycle.disable_all_for('before_tool_call')

# Deprecate a hook (handlers still run, but downstream can filter deprecated?)
lifecycle.deprecate_hook('old_hook')
```

## Observability

```ruby
reporter = WildHookOps::Health::Reporter.new(
  monitor:  HOOK_MONITOR,
  registry: HOOK_REGISTRY
)

# Summary (for dashboards or health endpoints)
summary = reporter.summary
# => {
#   total_handlers_tracked: 3,
#   total_calls: 1450,
#   total_errors: 2,
#   slow_handlers: ['handler_before_tool_call_...'],
#   stale_handlers: ['handler_on_error_...'],
#   ...
# }

# Detailed per-handler metrics
reporter.detailed.each { |m| log_metric(m) }

# Audit trail queries
HOOK_AUDIT.trail.for_hook('before_tool_call').last(100).each do |event|
  puts "#{event.timestamp}: #{event.outcome} in #{event.duration_ms}ms"
end

HOOK_AUDIT.trail.by_outcome(:error).each do |event|
  alert_ops("Handler #{event.handler_id} failed: #{event.error_message}")
end
```

## Operational Thresholds

| Signal | Default threshold | Action |
|--------|-------------------|--------|
| Slow handler | avg > 1_000ms | Investigate or increase timeout |
| Failing handler | error_rate > 0.5 | Disable or fix handler |
| Stale handler | never called | Review if still needed |

## Draining the Audit Trail

The trail is an in-memory ring buffer. For long-running processes, periodically drain and persist:

```ruby
# Drain trail to persistent store
events = HOOK_AUDIT.trail.all
MyPersistenceLayer.insert_batch(events.map(&:to_h))
HOOK_AUDIT.trail.clear!
```

## Thread Safety

All stores (DefinitionStore, HandlerStore, Trail, Monitor) use Mutex internally. It is safe to register handlers and execute hooks concurrently.
