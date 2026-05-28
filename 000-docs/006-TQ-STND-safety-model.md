# 006 — Safety Model: wild-hook-ops

## Threat Model

Hook-ops executes arbitrary user-provided callables. The safety model describes the isolation guarantees provided and the boundaries that are explicitly not enforced.

## Isolation Guarantees

### Per-Handler Error Isolation

Every handler execution is wrapped in `ErrorIsolator`. Any exception that is a subclass of `StandardError` is caught, recorded as a `:error` outcome, and does not propagate up the execution chain. Subsequent handlers continue to execute unless `on_handler_error: :halt` is configured.

This means one buggy or hostile handler cannot crash the entire hook chain.

### Per-Handler Timeout Isolation

Every handler execution is wrapped in `TimeoutGuard` using Ruby's `Timeout` stdlib. If the handler exceeds `timeout_ms`, it receives a `Timeout::Error` which is caught at the guard level and recorded as a `:timeout` outcome. The handler is aborted.

**Caveat:** Ruby's `Timeout.timeout` raises `Timeout::Error` into the handler's thread at a random point. This is safe for most handlers but can leave non-atomic operations in a partially completed state. Handlers that open connections or write files should use their own internal timeouts rather than relying solely on TimeoutGuard.

### Signal Exceptions Are NOT Isolated

`SignalException`, `Interrupt`, and `Timeout::Error` (when raised inside the isolator rather than the guard) are re-raised and will propagate. This is intentional: process signals must be able to shut down the process cleanly.

## What Is NOT Enforced

- **Handler identity/authorship** — anyone with access to the registry can register a handler. There is no signing or provenance verification.
- **Permissions** — `required_permissions` on HookDefinition is advisory metadata. Hook-ops does not enforce it. The consuming application is responsible for verifying handler registration against permissions.
- **Side effect containment** — a handler can do anything its callable does (write files, make network calls, mutate shared state). Hook-ops does not sandbox at the OS or language level.
- **Input sanitization** — the context hash passed to handlers is passed by reference. Handlers can mutate it. Consumers that require immutable context should pass `context.freeze` or a deep copy.

## Configuration Risks

| Configuration | Risk if misconfigured |
|--------------|----------------------|
| `on_handler_error: :halt` | One transient error in a high-priority handler blocks all subsequent handlers |
| `default_timeout_ms` too low | Legitimate slow handlers produce spurious `:timeout` outcomes |
| `max_handlers_per_hook` too high | Memory growth if handlers accumulate without cleanup |
| `enable_audit_logging: false` | No audit trail — loss of observability |
| `max_audit_entries` too low | Audit trail evicts important events under load |

## Recommendations

1. Use `:log_and_continue` in production unless you have a specific reason to halt
2. Set per-handler `timeout_ms` for handlers with known latency profiles rather than relying on the global default
3. Monitor `failing_handlers` and `stale_handlers` via `Health::Reporter` and alert on degradation
4. Drain and persist the audit trail periodically in long-running services
5. Do not pass sensitive data (credentials, tokens) in the context hash unless all handlers are trusted
