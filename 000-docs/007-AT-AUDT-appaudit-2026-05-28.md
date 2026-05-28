# 007 — Operator-Grade System Audit: wild-hook-ops

**Document type:** Audit report
**Filed as:** `007-AT-AUDT-appaudit-2026-05-28.md`
**Audit date:** 2026-05-28
**Audience:** Senior Ruby/Rails engineer, first read, must be operating in 10 minutes
**Subject:** `wild-hook-ops` v0.1.0 — 1 of 10 gems in the `wild` ecosystem
**Status at audit time:** v1 complete (10 epics, 247 specs green, 0 RuboCop offenses) — **not yet adopted by either of its intended consumers**

---

## 1. Mission and Boundaries

`wild-hook-ops` is a centralized hook lifecycle library for agent-workflow extension points. The mental model is "git hooks for agent workflows": a tool fires a named hook at a well-defined boundary (e.g. `before_tool_call`), and any number of registered handlers run in deterministic priority order with timeouts, error isolation, audit recording, and health metrics. The gem is pure Ruby, depends only on the stdlib `Timeout` library, and exposes one root module: `WildHookOps`.

The gem's archetype in the wild taxonomy is **C — SDLC Companion**: it is not customer-facing, not security-critical on its own, and not an MCP server. It is a foundational library that other wild gems consume. The mission statement in `CLAUDE.md` lines 7–9 makes the framing explicit: registration, execution, auditing, and health monitoring for hook/extension points in agent workflows.

**What it does:**

- Registers immutable hook *definitions* (`Models::HookDefinition`) — a named extension point with a trigger symbol, required permissions, version, and deprecated flag.
- Registers mutable hook *handlers* (`Models::HookHandler`) — a callable, priority, optional per-handler timeout, enabled flag, metadata.
- Executes all enabled handlers for a hook in ascending priority order under per-handler `Timeout.timeout` and `StandardError` isolation (`Execution::Runner`).
- Records every execution as an immutable `HookEvent` in a capped ring-buffer audit trail (`Audit::Logger` + `Audit::Trail`).
- Tracks per-handler counters (calls, successes, errors, timeouts, total duration) and exposes slow/failing/stale-handler queries (`Health::Monitor` + `Health::Reporter`).
- Manages lifecycle transitions — enable, disable, deprecate, version bump — via `Lifecycle::Manager` and a `Lifecycle::VersionTracker`.

**What it explicitly does not do:**

- **No persistence.** The audit trail is an in-process ring buffer. There is no disk, no SQLite, no external store. If the process dies, audit history dies with it. `000-docs/003-AT-ADEC-architecture-decisions.md` AD-003 makes this explicit and tells consumers to drain the trail themselves if they need durability.
- **No parallel execution.** `Configuration#execution_mode` accepts `:parallel`, but the Runner ignores it. AD-008 documents this as a reserved interface, not a feature.
- **No transport / IPC / network code.** Hook-ops is a library, not a server. It does not know about MCP, HTTP, or any wire protocol. Consumers wire it into their own tool boundaries.
- **No automatic registration of handlers from the filesystem, config files, or DSLs.** Every handler is registered programmatically through `HookRegistry#register_handler`.
- **No permission enforcement.** `HookDefinition#required_permissions` is metadata only — the registry does not check whether a caller registering a handler has the permissions the definition declares. Enforcement is the consumer's job (and the most plausible v2 integration point with `wild-capability-gate`).
- **No cross-process coordination.** All state lives in-process; two Ruby workers each get their own registry, audit trail, and monitor.

---

## 2. Hook Lifecycle Architecture

The gem decomposes the hook lifecycle into four orthogonal subsystems — **registry**, **execution**, **audit**, **health** — plus a thin **lifecycle** facade for enable/disable/deprecate operations. Each subsystem is in its own namespace under `lib/wild_hook_ops/`. The entry point file `lib/wild_hook_ops.rb` does nothing more than `require_relative` every component and expose module-level `configure` / `configuration` / `reset_configuration!`.

### 2.1 Registry layer (`lib/wild_hook_ops/registry/`)

Two stores, one facade:

- `DefinitionStore` (`registry/definition_store.rb`) — a `Mutex`-guarded `Hash` keyed by hook name. Holds `HookDefinition` values. Operations: `register`, `fetch` (raises `HookNotFoundError`), `find` (nil-safe), `registered?`, `all`, `active`, `deprecated`, `by_trigger`, `clear!`.
- `HandlerStore` (`registry/handler_store.rb`) — a `Mutex`-guarded `Hash` whose values are `Array<HookHandler>`. Enforces a per-hook cap (`max_handlers_per_hook`, default 20) at registration time, raising `HandlerLimitExceededError`. Provides `for_hook`, `enabled_for_hook`, `find_by_id`, `all`, `total_count`.
- `HookRegistry` (`registry/hook_registry.rb`) — composes the two stores. `define(name:, trigger:, …)` constructs a `HookDefinition` and registers it. `register_handler(hook_name:, callable:, …)` requires the definition exists (raises `HookNotFoundError` otherwise) and then constructs and registers a `HookHandler`. `handlers_for(hook_name)` returns enabled handlers sorted by ascending priority — this is the read-side used by the Runner.

### 2.2 Execution layer (`lib/wild_hook_ops/execution/`)

Three classes form a tiny pipeline:

- `TimeoutGuard` (`execution/timeout_guard.rb`) — wraps a block in `Timeout.timeout`, returns `[:ok, value, duration_ms]` or `[:timeout, nil, duration_ms]`. Uses `Process.clock_gettime(Process::CLOCK_MONOTONIC)` for duration measurement, which is the correct choice (wall-clock-immune).
- `ErrorIsolator` (`execution/error_isolator.rb`) — catches `StandardError` and returns `[:error, exception]`; explicitly re-raises `Timeout::Error` and `SignalException` so the surrounding `TimeoutGuard` can record the timeout outcome and so `Interrupt` / `SIGTERM` propagate for graceful shutdown. AD-005 documents this layering decision.
- `Runner` (`execution/runner.rb`) — the orchestrator. For each enabled handler returned by `registry.handlers_for(hook_name)`, it wraps `handler.call(context)` inside an isolator inside a timeout guard, builds a `HookResult`, records it to the audit logger (if wired) and the health monitor (if wired), and either continues or halts depending on `Configuration#on_handler_error`.

### 2.3 Audit layer (`lib/wild_hook_ops/audit/`)

- `Trail` (`audit/trail.rb`) — a `Mutex`-guarded `Array` of `HookEvent`. On overflow it `shift`s the oldest entry. Queryable by hook name, outcome, handler ID, or time range.
- `Logger` (`audit/logger.rb`) — converts a `HookResult` plus the originating context hash into a `HookEvent` (with context summarized to a 200-char string by `HookEvent#truncate`) and appends to the trail. Respects `Configuration#enable_audit_logging` — when false, `record` is a no-op.

### 2.4 Health layer (`lib/wild_hook_ops/health/`)

- `Monitor` (`health/monitor.rb`) — keeps a `Hash` keyed by handler ID, value is a mutable `Metrics` `Struct` (call_count, success/error/timeout counts, total_duration_ms; derived: `avg_duration_ms`, `error_rate`, `success_rate`). All mutation under a `Mutex`. AD-007 explains the mutable-Struct-inside-Mutex choice as an allocation optimization.
- `Reporter` (`health/reporter.rb`) — surfaces `summary` (totals + slow/failing/stale lists) and `detailed` (per-handler hashes) views, plus per-handler `for_handler(id)`. Stale-handler detection requires a registry reference; without one, `stale_handlers` returns `[]`.

### 2.5 Lifecycle layer (`lib/wild_hook_ops/lifecycle/`)

- `VersionTracker` — append-only history of `(hook_name, version, changed_at)` entries.
- `Manager` — enable/disable single handlers or all handlers under a hook; deprecate a hook; bump a hook's version. Deprecation and version-bump use `instance_variable_set` on `HookDefinition` (AD-006 calls this an intentional privileged operation, not a workaround).

The four subsystems are wired together at the consumer's discretion. Hook-ops itself never assumes a particular topology — `Runner` accepts `audit_logger:` and `health_monitor:` as `nil` and skips the corresponding recording calls when absent (`runner.rb:30–31`). This is the AD-002 constructor-injection-everywhere style.

---

## 3. The Critical Path

The representative end-to-end flow is "an agent reaches a hook point, all registered handlers fire, audit captured, health updated." This is what `Execution::Runner#execute` does (`lib/wild_hook_ops/execution/runner.rb:23–43`):

1. **Caller invokes the hook.** Consumer code does `runner.execute('before_tool_call', { tool: 'bash', user: 'alice' })`. The Runner checks `@registry.hook_defined?(hook_name)` and raises `HookNotFoundError` if no `HookDefinition` is registered. This is the only fail-fast in the path — unknown hook names are caller bugs, not runtime concerns.
2. **Resolve handler list.** `@registry.handlers_for(hook_name)` calls `HandlerStore#enabled_for_hook(hook_name)` (filter out `enabled == false`) then `.sort_by(&:priority)` (ascending — lower priority runs first). Disabled handlers are silently skipped; there is no "skipped" `HookResult` emitted for them. This is a design choice with a tradeoff (see §6, ADR T-2).
3. **Per-handler loop.** For each handler in priority order, `Runner#execute_handler` (runner.rb:48–67) runs:
   - Resolve effective timeout: `handler.timeout_ms || @config.default_timeout_ms`.
   - Construct a `TimeoutGuard` and call `guard.call do … end`.
   - Inside the guard, construct/use the shared `ErrorIsolator` and call `isolator.call { handler.call(context) }`.
   - The isolator returns `[:ok, return_value]` or `[:error, StandardError]`.
   - The guard returns `[:ok, [status, value], duration_ms]` or `[:timeout, nil, duration_ms]`.
4. **Build the `HookResult`.** Three outcomes are possible:
   - `:timeout` — handler exceeded its budget; `error` and `return_value` are both nil.
   - `:error` — handler raised a `StandardError`; the exception object is attached.
   - `:success` — handler returned normally; `return_value` carries whatever it produced.
5. **Record to audit + health.** `@audit_logger&.record(result, context)` builds a `HookEvent` (summarized context, error message extracted) and appends to the trail. `@health_monitor&.record(result)` increments the per-handler counters. Both calls are nil-safe — if the consumer constructed the Runner without wiring an audit logger or a monitor, the corresponding recording is silently skipped.
6. **Halt-or-continue decision.** If the result is `:error` *and* `@config.on_handler_error == :halt`, the loop breaks; remaining handlers do not run. Otherwise the loop continues. Importantly, `:timeout` does **not** trigger halt — only explicit `StandardError`. This is unclear from the current code whether intentional; the spec at `spec/wild_hook_ops/execution/runner_spec.rb` does not assert one way for timeout-then-halt behavior.
7. **Return.** The Runner returns `Array<HookResult>` in execution order. The caller is responsible for any cross-handler decision logic (e.g. `if results.any?(&:error?) then abort` in the operator-guide pattern at `000-docs/005-OD-GUID-operator-guide.md:60–63`).

End-to-end, a single hook invocation is one allocation per handler for the `HookResult`, one `HookEvent` per handler if audit logging is enabled, and one in-place mutation of the `Metrics` Struct per handler if a monitor is wired. No I/O, no DB, no network.

---

## 4. Extraction Status — the Elephant in the Room

**`wild-hook-ops` v0.1.0 is shipped but not yet adopted.** The gem was extracted to generalize ad-hoc hook-emitter patterns that already exist in `wild-admin-tools-mcp` and `wild-rails-safe-introspection-mcp`, but neither consumer has been migrated. Neither consumer's `Gemfile` declares a dependency on `wild-hook-ops`. This is the most important fact in this audit.

### 4.1 The ad-hoc emitter in `wild-admin-tools-mcp`

The pattern lives **as a documented interface, not yet wired**: `wild-admin-tools-mcp/000-docs/018-AT-ADEC-telemetry-emission-hook-interface.md:37–58` defines a `WildAdminToolsMcp::Telemetry::HookEmitter` class with a single `emit(event)` method that swallows subscriber failures. Three hook points are identified in `018-…:29–33`:

| Hook point | Location | Event |
|---|---|---|
| After audit record creation | `Audit::Recorder#record` | `action.completed` |
| After gate evaluation | `Identity::AuthenticatedPipeline#authorize_via_gate` | `gate.evaluated` |
| After rate-limit check | `Guard::Pipeline#check_rate_limit!` | `rate_limit.checked` |

The doc explicitly labels the snippet as *"Conceptual — not yet wired in v1."* No `HookEmitter` class exists in `lib/wild_admin_tools_mcp/` today (confirmed via grep of the tree at `lib/wild_admin_tools_mcp/{audit,confirmation,executor,guard,identity,server}/` plus the four top-level files). So in admin-tools the "ad-hoc emitter pattern" is currently a planned interface that hook-ops can satisfy *before* it is hand-rolled.

### 4.2 The ad-hoc emitter in `wild-rails-safe-introspection-mcp`

Same shape, different progress: `wild-rails-safe-introspection-mcp/000-docs/019-AT-ADEC-telemetry-emission-hook-interface.md:119–179` defines a `WildRailsSafeIntrospection::Telemetry::Emitter` module with `emit(audit_record)` / `emit_lifecycle(event)` / `enabled?` and an `EventBuilder` that projects an `AuditRecord` into a privacy-reduced event. The doc identifies the hook point as inside the existing `Audit::Recorder` flow (lines 125–131). The active code at `lib/wild_rails_safe_introspection/audit/recorder.rb:11–16` shows `emit_audit_record(...)` already named with "emit" in the verb — a deliberate hint that the call site is the future hook injection point — but the actual telemetry `Emitter` module does not exist yet in `lib/wild_rails_safe_introspection/`. The doc is marked `Status: Planned — interface definition only, not yet implemented`.

### 4.3 Why "extracted-not-yet-adopted" is a v2 blocker

The whole rationale for hook-ops existing — per `CLAUDE.md:11` and the README — is that admin-tools and rails-introspection each were going to invent their own emitter and the wild ecosystem decided once was better than twice. If neither consumer adopts hook-ops, the gem solves a problem for nobody. Worse, if either consumer ships its own emitter first, hook-ops becomes a third pattern instead of the one.

### 4.4 Migration path per consumer

The mapping is mechanical. Both consumers need to:

1. **Add the gem.** Append `gem 'wild-hook-ops'` to the `Gemfile` (either rubygems-published or `git:` source, matching the `wild-capability-gate` dual-mode pattern already used by admin-tools).
2. **Construct one shared registry at boot.** Define the three hook points the existing emitter doc identifies. For admin-tools: `action.completed`, `gate.evaluated`, `rate_limit.checked`. For rails-introspection: `tool_invocation`, `server_startup`, `policy_loaded`.
3. **Replace the planned `emit(event)` call sites with `runner.execute('hook_name', context)`.** In admin-tools this is three call sites: `Audit::Recorder#record`, `Identity::AuthenticatedPipeline#authorize_via_gate`, `Guard::Pipeline#check_rate_limit!`. In rails-introspection it is one call site inside `Audit::Recorder.emit_audit_record` (`lib/wild_rails_safe_introspection/audit/recorder.rb:37`).
4. **Move the existing "telemetry subscriber" concept onto hook-ops as a handler.** A telemetry client that responds to `receive(event)` becomes a one-line lambda registered against the hook: `registry.register_handler(hook_name: 'action.completed', callable: ->(ctx) { telemetry_client.receive(ctx) })`.
5. **Delete the planned `HookEmitter` / `Emitter` interface docs and replace them with a short "uses wild-hook-ops" reference.** Keep the privacy-reduction `EventBuilder` logic from rails-introspection inside the handler body — that is application-specific projection, not generic.

Until those two PRs land, hook-ops is shelf-ware. **This is the single recommendation that should drive v2.**

---

## 5. Failure Modes and Blast Radius

The execution path is well-defended in places and silently lossy in others. The honest summary:

| Failure | What happens | Blast radius |
|---|---|---|
| Handler raises `StandardError` | `ErrorIsolator` catches it; `Runner` builds a `:error` `HookResult` with the exception attached; audit + health record it. If `on_handler_error: :halt`, remaining handlers skipped. | Bounded — single handler. Other handlers and the calling tool continue (unless `:halt`). |
| Handler raises `Timeout::Error` from inside its own code | Caught by the surrounding `TimeoutGuard` and reported as `:timeout`. Note: a handler that *itself* uses `Timeout.timeout` internally can produce a confusing trace. | Bounded — recorded as timeout. |
| Handler raises `SignalException` (e.g. `Interrupt`) | `ErrorIsolator` re-raises (AD-005). The whole `Runner#execute` call unwinds. Audit and health are **not** updated for the in-flight handler. | Wide — propagates out of the gem. Intentional for graceful shutdown. |
| Handler hangs forever (no signals, just blocks) | `Timeout.timeout` should fire and record `:timeout`. **Caveat:** `Timeout.timeout` uses a background thread and is known to be unreliable for blocked C extensions and uninterruptible syscalls. A handler stuck inside a `Mutex#synchronize` or `IO.select` may not be cleanly interruptible. | Potentially unbounded for the pathological case. Worth a v2 note. |
| Two threads register handlers for the same hook simultaneously | `HandlerStore#register` holds the mutex for the limit check + the append, so the cap is atomic. No race. | None. |
| Two threads execute the same hook simultaneously | `handlers_for` returns a duped array under the mutex; per-handler execution is unsynchronized; `Audit::Trail#append` and `Health::Monitor#record` each take their own mutex. Counters and trail stay consistent; handler bodies must handle their own re-entrancy. | None inside hook-ops; depends on handler code. |
| Audit storage "fails" | Cannot fail in the current implementation — there is no I/O. The trail is an `Array#push` under a `Mutex`, which only fails on `NoMemoryError`. The ring buffer caps memory. | None today; will matter when a persistent trail backend is added (v2). |
| Audit trail overflows `max_audit_entries` | Oldest entry silently dropped via `shift` (AD-003). No log, no signal, no callback. | Operational risk — lossy history without warning. |
| Health monitor never sees a handler (handler registered, never invoked) | `Reporter#summary[:stale_handlers]` surfaces it — *if* the reporter was constructed with a registry reference. Without the registry, stale detection silently returns `[]`. | Bounded — operator must remember to wire the registry. |
| `WildHookOps.configure` called after `freeze!` | `ConfigurationFrozenError` raised on the setter. | Bounded — fails fast at the setter call, not at first use. |
| Consumer forgets to wire `audit_logger:` or `health_monitor:` | `Runner` skips those calls silently (`runner.rb:30–31`). | Operational risk — observability gap with no warning. |

The pattern is clear: **failures inside handlers are well-contained, but configuration mistakes (no audit logger wired, registry omitted from reporter, audit overflow) fail silently**. None of these are wrong per se — they are the price of "library that gets out of the way" — but a senior engineer integrating this gem should know which silences are intentional.

---

## 6. Trade-off Analysis

The ADR document at `000-docs/003-AT-ADEC-architecture-decisions.md` records eight decisions, all well-reasoned and all worth re-evaluating in light of the extraction-status concern in §4. Three with the highest blast radius:

| ID | Chosen | Alternative | Why | Cost | When it breaks |
|---|---|---|---|---|---|
| **T-1 (AD-001 + AD-008)** | Stdlib-only, sequential-only execution | Pull in `concurrent-ruby`, implement parallel handler dispatch behind `execution_mode: :parallel` | Zero-dep policy keeps install surface tiny; the foundational-library role rewards conservative dependencies. Parallel was reserved (not implemented) because no consumer has a use case yet. | A handler that does I/O (HTTP call, DB hit) blocks all later handlers for its full timeout budget. Wall-clock latency scales linearly with handler count. | When a consumer chains 5+ I/O-bound handlers behind a synchronous tool call. Today neither admin-tools nor rails-introspection has that pattern, but a telemetry handler hitting an HTTP collector would. |
| **T-2 (filter-then-sort)** | `handlers_for` filters disabled handlers *before* sorting and Runner never emits a `:skipped` result for them | Always sort the full set, run disabled handlers through the Runner so a `:skipped` `HookResult` is produced for audit | Cheaper hot path (smaller list to sort); no audit noise from disabled handlers. | Disabled handlers leave no trace in the audit trail. Operators investigating "why didn't handler X run on event Y?" must consult registry state at investigation time, not the audit log. | When operators need a forensic record of which handlers were available-but-suppressed at the moment a hook fired. The `HookResult` model already has `:skipped` as a valid outcome (`models/hook_result.rb:5`) — it is reserved but never produced. |
| **T-3 (AD-003)** | Audit trail is an in-process capped ring buffer | Pluggable trail backend interface (memory / SQLite / external sink) | Keeps the gem zero-dep and zero-config. Consumers who need durability "should drain the trail periodically." | Audit history is lost on process restart. Long-running processes silently evict old events. No native way to ship events to a SIEM, S3, or a `wild-session-telemetry` backend. | The moment a consumer wants to satisfy a compliance requirement that says "audit records must survive a process restart" — which is the typical bar for the same hook events that admin-tools' audit-record interface already targets. v2 needs a `Trail` interface that the ring buffer is one implementation of. |

Two additional decisions worth flagging without full breakdowns:

- **AD-006 (`instance_variable_set` for lifecycle mutation of `HookDefinition`).** Pragmatic and explicit, but it punches a hole through "definitions are immutable." A consumer who introspects a definition with `to_h` cannot tell whether the version they see is the original or a mutated one without consulting `VersionTracker#history_for(name)`. Acceptable for v1; worth replacing with an explicit `definition.deprecate!` / `definition.bump_version!` API in v2 to make the mutation point a method, not a comment.
- **AD-004 (handler IDs encode `object_id`).** IDs are unique within a process but not stable across restarts. The audit trail correlates by handler ID; a process restart starts a fresh ID space, so historical audit entries cannot be correlated against currently-registered handlers. Today this is fine — the trail itself does not survive restart either (T-3). When T-3 is addressed, T-AD-004 becomes a paired problem: durable audit needs stable handler identity.

---

## 7. Operator Playbook

The integration shape is documented in `000-docs/005-OD-GUID-operator-guide.md`. Four operations every operator will do:

**Register a handler against an existing hook point.**

```ruby
HOOK_REGISTRY.register_handler(
  hook_name:  'before_tool_call',
  callable:   MyAuditService.method(:before_tool),
  priority:   10,           # lower runs first
  timeout_ms: 500,          # overrides config.default_timeout_ms
  metadata:   { source: 'my_audit_service' }
)
```

The hook must already be defined (`registry.define(name:, trigger:, …)`) or this raises `HookNotFoundError`. Over `max_handlers_per_hook` (default 20) raises `HandlerLimitExceededError`. A non-callable raises `InvalidHandlerError`.

**Inspect the audit trail.**

```ruby
# Last 100 events for a hook
HOOK_AUDIT.trail.for_hook('before_tool_call').last(100).each do |event|
  puts "#{event.timestamp}: #{event.outcome} in #{event.duration_ms}ms"
end

# All errors in a time window
HOOK_AUDIT.trail.in_range(from: 1.hour.ago, to: Time.now)
  .select { |e| e.outcome == :error }
```

Remember the trail is in-process and capped; for forensic work after a restart, the trail is gone.

**Recover from a handler crash.**

`StandardError` from a handler is already isolated and recorded as `:error`. Operator response:

1. Find the offender: `HOOK_AUDIT.trail.by_outcome(:error).last(20).map { |e| [e.handler_id, e.error_message] }`.
2. Confirm the handler still exists: `HOOK_REGISTRY.handler_store.find_by_id(handler_id)`.
3. Disable it without removing it: `lifecycle.disable_handler(handler_id)`. The handler stays registered (preserving its position in priority order for when re-enabled) but is filtered out by `handlers_for`.
4. Patch the handler code, redeploy, and `lifecycle.enable_handler(handler_id)`.

If the failure mode is `on_handler_error: :halt` and a handler is wedging an entire tool call, `lifecycle.disable_all_for(hook_name)` is the kill switch.

**Health check.**

```ruby
reporter = WildHookOps::Health::Reporter.new(monitor: HOOK_MONITOR, registry: HOOK_REGISTRY)
summary = reporter.summary
# Watch: summary[:failing_handlers] (error_rate > 0.5)
#        summary[:slow_handlers]    (avg_duration_ms > 1_000)
#        summary[:stale_handlers]   (registered but never called)
```

A non-empty `stale_handlers` list after a known-busy period is the cheapest signal that a handler was registered against the wrong hook name.

---

## 8. Recommendations for v2

1. **Adopt the gem in both consumers — this is the only recommendation that matters.** Open two PRs: one against `wild-admin-tools-mcp` that adds the gem, defines the three planned hooks (`action.completed`, `gate.evaluated`, `rate_limit.checked`), and wires `runner.execute` at the three call sites currently documented in `000-docs/018-AT-ADEC-telemetry-emission-hook-interface.md`. One against `wild-rails-safe-introspection-mcp` that adds the gem, defines `tool_invocation` / `server_startup` / `policy_loaded`, and replaces the planned `Telemetry::Emitter` module with a hook-ops handler at the call site in `lib/wild_rails_safe_introspection/audit/recorder.rb:37`. Until this lands, hook-ops is unproven in production.
2. **Replace the `instance_variable_set` lifecycle mutations with explicit `HookDefinition#deprecate!` / `#bump_version!` methods.** Trivial change, removes a foot-gun.
3. **Introduce a `Trail` interface; keep the ring buffer as the default implementation.** Lets consumers ship audit events to a persistent backend (SQLite, S3, a future `wild-session-telemetry` collector) without forking the gem. Pair with stable, restart-portable handler IDs so historical audit data can be correlated.
4. **Emit `:skipped` `HookResult` entries for disabled handlers** (or document loudly that disabled handlers leave no audit trace). The `:skipped` outcome already exists in the model layer; producing it would close a forensic gap.
5. **Surface ring-buffer eviction.** Either an `on_evict` callback on `Trail` or a counter exposed via `Trail#evicted_count`. Silent loss of audit history is the kind of thing that bites once and is then never trusted.
6. **Decide on `:halt` semantics for `:timeout`.** The current code halts only on `:error`, not `:timeout`. Either codify that as deliberate in `005-OD-GUID-operator-guide.md` or extend the halt check to include both.

---

**End of audit.**

---

## Brief Report

`wild-hook-ops` v0.1.0 is technically complete (247 specs, 0 RuboCop offenses) and well-architected: clean four-subsystem split (registry / execution / audit / health), zero non-stdlib deps, sound mutex discipline, defensible ADRs. The single material issue is **extraction-without-adoption** — the gem generalizes hook patterns from two consumers, but neither consumer's Gemfile declares it and both still describe the pattern as "planned" in their own docs. Without consumer adoption, hook-ops is shelf-ware and the next session of either consumer will be tempted to hand-roll the emitter instead. v2 must lead with the two consumer-adoption PRs. Secondary v2 work — `Trail` interface, explicit lifecycle mutations, `:skipped` results, eviction visibility — is real but lower priority.

**Cross-repo emitter paths the adoption PRs must replace:**

- `/home/jeremy/000-projects/wild/wild-admin-tools-mcp/000-docs/018-AT-ADEC-telemetry-emission-hook-interface.md:37-58` (planned `HookEmitter` class; not yet wired)
- `/home/jeremy/000-projects/wild/wild-admin-tools-mcp/000-docs/018-AT-ADEC-telemetry-emission-hook-interface.md:29-33` (three call sites: `Audit::Recorder#record`, `Identity::AuthenticatedPipeline#authorize_via_gate`, `Guard::Pipeline#check_rate_limit!`)
- `/home/jeremy/000-projects/wild/wild-rails-safe-introspection-mcp/000-docs/019-AT-ADEC-telemetry-emission-hook-interface.md:119-179` (planned `Telemetry::Emitter` module; not yet implemented)
- `/home/jeremy/000-projects/wild/wild-rails-safe-introspection-mcp/lib/wild_rails_safe_introspection/audit/recorder.rb:11-16,37-43` (active code with `emit_audit_record` named as the future hook injection point)
