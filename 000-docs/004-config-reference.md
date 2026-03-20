# 004 — Configuration Reference: wild-hook-ops

## Overview

`WildHookOps::Configuration` holds all runtime configuration. Access via `WildHookOps.configure` or `WildHookOps.configuration`.

After calling `freeze!`, all mutation raises `ConfigurationFrozenError`.

## Keys

### `default_timeout_ms`

- **Type:** Integer
- **Default:** `5_000`
- **Constraint:** positive integer
- **Description:** The timeout applied to each handler execution when the handler does not specify its own `timeout_ms`. Measured in milliseconds.

```ruby
WildHookOps.configure { |c| c.default_timeout_ms = 2_000 }
```

---

### `max_handlers_per_hook`

- **Type:** Integer
- **Default:** `20`
- **Constraint:** positive integer
- **Description:** Maximum number of handlers that can be registered for a single hook name. Attempting to register a handler beyond this limit raises `HandlerLimitExceededError`.

```ruby
WildHookOps.configure { |c| c.max_handlers_per_hook = 50 }
```

---

### `enable_audit_logging`

- **Type:** Boolean
- **Default:** `true`
- **Description:** When `false`, `Audit::Logger#record` returns nil and writes nothing to the trail. Useful in high-throughput test environments or benchmarks.

```ruby
WildHookOps.configure { |c| c.enable_audit_logging = false }
```

---

### `max_audit_entries`

- **Type:** Integer
- **Default:** `10_000`
- **Constraint:** positive integer
- **Description:** Maximum entries in the audit trail ring buffer. When this limit is reached, the oldest entry is evicted on each new append.

```ruby
WildHookOps.configure { |c| c.max_audit_entries = 50_000 }
```

---

### `execution_mode`

- **Type:** Symbol
- **Default:** `:sequential`
- **Valid values:** `:sequential`, `:parallel`
- **Description:** Controls how handlers are executed. `:parallel` is reserved for future use — Runner always executes sequentially in the current version.

```ruby
WildHookOps.configure { |c| c.execution_mode = :sequential }
```

---

### `on_handler_error`

- **Type:** Symbol
- **Default:** `:log_and_continue`
- **Valid values:** `:log_and_continue`, `:halt`
- **Description:** Controls Runner behavior when a handler produces `:error` or `:timeout` outcome.
  - `:log_and_continue` — records the result and continues to the next handler
  - `:halt` — stops execution after the first failure

```ruby
WildHookOps.configure { |c| c.on_handler_error = :halt }
```

---

## `freeze!`

Locks the configuration. Any subsequent mutation raises `ConfigurationFrozenError`. Intended for production use where configuration should be finalized at boot time.

```ruby
WildHookOps.configure do |c|
  c.default_timeout_ms = 3_000
  c.freeze!
end
```

## `reset_configuration!`

Creates a fresh `Configuration` instance with all defaults. Used in tests via `before { WildHookOps.reset_configuration! }`.

```ruby
WildHookOps.reset_configuration!
```
