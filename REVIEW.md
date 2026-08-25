# REVIEW.md

Repository-specific law for the automated pull-request reviewer (MiniMax, two advisory lanes).

wild-hook-ops is a zero-dependency Ruby gem that executes arbitrary third-party callables on behalf
of AI agents: registration, priority-ordered execution with per-handler timeout and error isolation,
an audit trail, and per-handler health metrics. Consumers in the wild ecosystem hang privileged
checks such as `before_tool_call` and `on_capability_check` off it. If this library silently drops a
handler, misreports an outcome, or leaks the context hash, a capability gate somewhere upstream
becomes decorative. Review for that, in that order of risk.

Report only defects the pull request introduces, and verify each against the surrounding source
before writing it. Advisory only: CI (`bundle exec rspec` on Ruby 3.2 and 3.3, plus `bundle exec
rubocop`) is the gate.

## Authority

`000-docs/006-TQ-STND-safety-model.md` (isolation guarantees and explicit non-guarantees) and
`000-docs/003-AT-ADEC-architecture-decisions.md` (AD-001 through AD-008) govern behavior questions;
`CLAUDE.md` covers conventions. A pull request that changes a guarantee without updating the safety
model is incomplete, and so is one that contradicts an AD without recording a superseding decision.
The PR description is a claim, never an authority.

## Top defect classes to hunt

1. **Isolation escape.** `ErrorIsolator` rescues `StandardError` and returns `[:error, e]`. Anything
   that lets a handler exception reach `Runner#execute`'s caller breaks the core promise that one
   hostile handler cannot crash the chain. Equally a defect in the other direction: rescuing
   `Exception`, or rescuing `Timeout::Error` or `SignalException` inside the isolator, would swallow
   the guard's own timeout signal and block process shutdown (AD-005).
2. **Timeout reclassified or not enforced.** The nesting order is load bearing: `TimeoutGuard` wraps
   `ErrorIsolator`, so `Timeout::Error` crosses the isolator untouched and is caught by the guard,
   which returns `[:timeout, nil, duration_ms]`. Invert that nesting and every timeout is recorded
   as `:error` or, worse, as `:success`. Flag any change to `Runner#execute_handler`'s wrapping, to
   the `[:ok | :timeout, value, duration]` tuple shape, or to the `handler.timeout_ms ||
   config.default_timeout_ms` resolution.
3. **A handler that should run does not, or one that should not does.** `HookRegistry#handlers_for`
   must return only `enabled?` handlers, sorted by `priority` ascending. Dropping the enabled filter
   runs a handler an operator deliberately quarantined through `Lifecycle::Manager#disable_handler`.
   Dropping or reversing the sort runs a validation step after the thing it was meant to validate.
   Both are silent.
4. **Context and error text leaking into the audit trail.** `Audit::Logger#summarise_context`
   builds `"#{k}=#{v.inspect}"` for every pair of the caller's context hash, so each key is
   interpolated through `to_s` and each value is `inspect`ed, into `HookEvent#context_summary`, and
   the raw `error.message` goes into `error_message`. The only containment is
   `HookEvent::CONTEXT_SUMMARY_MAX_LENGTH` truncation and the documented rule that callers must not
   put credentials in context. Treat any widening as a leak: removing the truncation, adding a
   backtrace, adding a new field that carries caller data, logging the context anywhere else, or
   ignoring `enable_audit_logging`. Never reproduce a suspected secret in a review comment; name the
   location and the fix.
5. **Unbounded growth.** `Audit::Trail` is a ring buffer that shifts when `size >= max_entries`;
   `HandlerStore` refuses past `max_per_hook`; `HookEvent` truncates. These are the memory caps of a
   long-running agent process. Removing a cap, making one advisory, or defaulting it to nil is a
   denial-of-service class, not a tuning change. Note `HandlerStore`'s `Hash.new { |h, k| h[k] = [] }`
   default block: a read of an unknown hook name creates a key, so new read paths can grow the hash.
6. **Concurrency defects.** Every store guards state with a `Mutex` and returns `dup`ed collections.
   Flag: state touched outside `synchronize`; an internal array or Struct returned without `dup`;
   nested `synchronize` on the same mutex (Ruby's Mutex is not reentrant, so that deadlocks); and
   check-then-act split across two separate `synchronize` calls, which is a real race
   (`DefinitionStore#register` already checks for a duplicate in one block and inserts in another).
   `Health::Monitor::Metrics` is a mutable Struct by design (AD-007) and may only be mutated inside
   the monitor's mutex.
7. **Correctness of what the caller is told.** `HookResult` outcome, `duration_ms`, `error`, and
   `return_value` are the entire contract. A `:success` for work that did not complete, a duration
   measured with wall clock instead of `Process::CLOCK_MONOTONIC`, or an `:error` result carrying a
   nil error, are defects even when nothing raises.

## Invariants that must never regress

- **Zero runtime dependencies.** The gemspec declares no runtime dependency at all. Ruby stdlib
  only: `timeout` is the single explicit `require`, and `Enumerable#to_set` is used once without a
  `require 'set'` of its own. Anything added to the gemspec's runtime dependencies violates AD-001,
  and suggesting ActiveSupport or concurrent-ruby is not a review comment, it is a rejected
  decision.
- **Ruby floor is 3.2.** The gemspec declares it and CI runs 3.2 and 3.3. Syntax or methods newer
  than 3.2 break the floor.
- **Handler exceptions never propagate; signals always do.**
- **Every executed handler produces exactly one `HookResult`, and it is recorded to the audit logger
  and the health monitor before any `:halt` break.** That ordering is why the failure that stopped
  the chain is still visible.
- **`instance_variable_set` on a model is confined to `Lifecycle::Manager`** (AD-006). Anywhere else
  it is a defect, and a public setter on `HookDefinition` or `HookEvent` is a design change.
- **Handler IDs are process-scoped and not serializable** (AD-004). Flag any code that persists them
  or assumes stability across restarts.
- **`required_permissions` is advisory metadata and this gem does not enforce it** (safety model).
  Treating it as enforcement is a new security boundary and needs the safety model updated in the
  same change.

## What "fail closed" means here

The chain is deliberately fail-open by default at the *policy* level (`on_handler_error:
:log_and_continue` keeps later handlers running). Fail closed applies to the *reporting* level: a
condition this library cannot honestly handle must raise, not degrade quietly.

- Executing an undefined hook raises `HookNotFoundError`. It must never return `[]`, which a caller
  cannot distinguish from "no handlers registered".
- Registering past `max_handlers_per_hook` raises `HandlerLimitExceededError`. It must never silently
  drop the handler.
- A duplicate definition raises `DuplicateHookError`. It must never overwrite.
- A callable that does not respond to `#call` is rejected at registration. An invalid `priority`
  or `timeout_ms` raises inside the `HookHandler` constructor, which is the only place that
  validates them, since neither has a public setter. An invalid config value raises at the
  `Configuration` setter. Validation moves earlier, never later.
- Mutating a frozen `Configuration` raises `ConfigurationFrozenError`.

Turning any of those raises into a `nil`, a `false`, or an empty array is a top-severity finding.

## Generated, vendored, and out of scope

`Gemfile.lock` is gitignored and must not be committed; neither may `pkg/`, `coverage/`, `doc/`, or
`*.gem` artifacts. `lib/wild_hook_ops/version.rb` and `CHANGELOG.md` move together on a release, so
flag one without the other. `000-docs/000-INDEX.md` must gain a row when a numbered document lands.

## What not to waste a comment on

- Anything RuboCop already enforces: line length, `# frozen_string_literal: true`, method length,
  complexity metrics, the aligned-assignment house style, RSpec structural cops. The `.rubocop.yml`
  exclusions are deliberate.
- Re-litigating AD-008: `execution_mode: :parallel` is accepted by config and intentionally not
  implemented in `Runner`. Only flag it if a change claims parallel execution works.
- Proposing a dependency, a new persistence layer, or OS-level sandboxing. The safety model states
  plainly that side-effect containment and handler provenance are not enforced here and belong to
  the consuming application.
- Test style preferences. Do flag a behavioral change to `lib/` that arrives with no matching spec,
  especially one touching isolation, timeout, or ordering, where `spec/adversarial/` is the home.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved and do not
invent new objections on unchanged lines you already accepted. Prefer a few high-conviction findings
over breadth. If the change is correct, safe, and consistent with the safety model, reply `lgtm`.
The reviewer is advisory and never blocks a merge.

## Sources

Every code-grounded claim above was read against the source at commit `9cb118b`, the head of this
pull request's branch. Line numbers are that commit's. Three claims did not survive the check and
were corrected in place before this section was written: the audit summariser interpolates keys and
inspects only values, `priority` and `timeout_ms` are validated in a constructor rather than at a
setter, and `set` is used without being required.

**Isolation and signals (defect class 1, AD-005)**

- ErrorIsolator rescues StandardError, returns `[:error, e]`: `lib/wild_hook_ops/execution/error_isolator.rb:15-16`
- Timeout::Error and SignalException re-raised, never swallowed: `lib/wild_hook_ops/execution/error_isolator.rb:13-14`
- `[:ok, return_value]` on the success path: `lib/wild_hook_ops/execution/error_isolator.rb:11-12`
- Isolator is what wraps the caller's handler call: `lib/wild_hook_ops/execution/runner.rb:50`
- AD-005 records the decision: `000-docs/003-AT-ADEC-architecture-decisions.md:43-49`
- Safety model states the same guarantee and its signal exception: `000-docs/006-TQ-STND-safety-model.md:11-13`, `000-docs/006-TQ-STND-safety-model.md:23`

**Timeout (defect class 2)**

- TimeoutGuard wraps ErrorIsolator, in that order: `lib/wild_hook_ops/execution/runner.rb:49-52`
- `[:ok, value, duration_ms]` and `[:timeout, nil, duration_ms]` tuple shape: `lib/wild_hook_ops/execution/timeout_guard.rb:20`, `lib/wild_hook_ops/execution/timeout_guard.rb:23`
- `handler.timeout_ms || config.default_timeout_ms` resolution: `lib/wild_hook_ops/execution/runner.rb:46`
- `Timeout.timeout` call and its rescue: `lib/wild_hook_ops/execution/timeout_guard.rb:18`, `lib/wild_hook_ops/execution/timeout_guard.rb:21`
- Outcome mapping from tuple to HookResult: `lib/wild_hook_ops/execution/runner.rb:54-63`

**Ordering and enablement (defect class 3)**

- `handlers_for` selects enabled then sorts by priority ascending: `lib/wild_hook_ops/registry/hook_registry.rb:49-51`
- The `enabled?` filter itself: `lib/wild_hook_ops/registry/handler_store.rb:32-34`
- `enabled?` alias on the handler: `lib/wild_hook_ops/models/hook_handler.rb:19-21`
- `Lifecycle::Manager#disable_handler` is how an operator quarantines one: `lib/wild_hook_ops/lifecycle/manager.rb:23-27`, backed by `lib/wild_hook_ops/models/hook_handler.rb:44-47`
- Lower priority runs first, as documented on the model: `lib/wild_hook_ops/models/hook_handler.rb:8-9`

**Audit containment (defect class 4)**

- `summarise_context` interpolates keys, inspects values: `lib/wild_hook_ops/audit/logger.rb:38`
- Empty and non-Hash context short-circuit: `lib/wild_hook_ops/audit/logger.rb:36`
- Summary and raw `error.message` onto the event: `lib/wild_hook_ops/audit/logger.rb:23-24`
- `enable_audit_logging` early return: `lib/wild_hook_ops/audit/logger.rb:16`
- `CONTEXT_SUMMARY_MAX_LENGTH` and the truncation that applies it: `lib/wild_hook_ops/models/hook_event.rb:7`, `lib/wild_hook_ops/models/hook_event.rb:54-58`, applied at `lib/wild_hook_ops/models/hook_event.rb:25`
- The documented caller rule, which is conditional on handler trust: `000-docs/006-TQ-STND-safety-model.md:48`

**Caps and growth (defect class 5)**

- Trail shifts when `size >= max_entries`: `lib/wild_hook_ops/audit/trail.rb:20-23`
- HandlerStore refuses past `max_per_hook`: `lib/wild_hook_ops/registry/handler_store.rb:19-20`
- The default block that creates a key on read of an unknown hook name: `lib/wild_hook_ops/registry/handler_store.rb:8`, read paths at `lib/wild_hook_ops/registry/handler_store.rb:29`, `lib/wild_hook_ops/registry/handler_store.rb:33`, `lib/wild_hook_ops/registry/handler_store.rb:51`
- Cap defaults and their validation: `lib/wild_hook_ops/configuration.rb:17`, `lib/wild_hook_ops/configuration.rb:19`, `lib/wild_hook_ops/configuration.rb:33-39`, `lib/wild_hook_ops/configuration.rb:49-55`
- AD-003 records the ring buffer: `000-docs/003-AT-ADEC-architecture-decisions.md:23-29`

**Concurrency (defect class 6)**

- Mutex-guarded stores: `lib/wild_hook_ops/registry/handler_store.rb:10`, `lib/wild_hook_ops/registry/definition_store.rb:9`, `lib/wild_hook_ops/audit/trail.rb:13`, `lib/wild_hook_ops/health/monitor.rb:57`
- Duped collections out of the stores: `lib/wild_hook_ops/registry/handler_store.rb:29`, `lib/wild_hook_ops/registry/handler_store.rb:47`, `lib/wild_hook_ops/audit/trail.rb:29`, `lib/wild_hook_ops/health/monitor.rb:71`
- The existing check-then-act split across two `synchronize` calls: `lib/wild_hook_ops/registry/definition_store.rb:15` and `lib/wild_hook_ops/registry/definition_store.rb:17`
- Metrics Struct, mutated only inside the monitor's mutex: `lib/wild_hook_ops/health/monitor.rb:12-53`, mutation at `lib/wild_hook_ops/health/monitor.rb:112-119` reached only through `lib/wild_hook_ops/health/monitor.rb:63`
- AD-007 records the mutable Struct: `000-docs/003-AT-ADEC-architecture-decisions.md:63-69`

**Honest results (defect class 7)**

- HookResult's contract fields: `lib/wild_hook_ops/models/hook_result.rb:9-14`, constructed at `lib/wild_hook_ops/execution/runner.rb:66-74`
- Valid outcomes and the raise on anything else: `lib/wild_hook_ops/models/hook_result.rb:7`, `lib/wild_hook_ops/models/hook_result.rb:60-65`
- Duration measured with `Process::CLOCK_MONOTONIC`: `lib/wild_hook_ops/execution/timeout_guard.rb:17`, `lib/wild_hook_ops/execution/timeout_guard.rb:28-30`

**Invariants**

- No runtime dependency declared anywhere in the gemspec: `wild-hook-ops.gemspec:1-21`
- The single explicit stdlib require: `lib/wild_hook_ops/execution/timeout_guard.rb:3`
- `Enumerable#to_set` used without its own require: `lib/wild_hook_ops/health/monitor.rb:88`
- AD-001, no external dependencies: `000-docs/003-AT-ADEC-architecture-decisions.md:3-9`
- Ruby floor 3.2 in the gemspec, in RuboCop, and in the CI matrix: `wild-hook-ops.gemspec:15`, `.rubocop.yml:5`, `.github/workflows/ci.yml:14`
- Every executed handler yields one HookResult, recorded to audit and health before the `:halt` break: `lib/wild_hook_ops/execution/runner.rb:30-38`, with the break itself at `lib/wild_hook_ops/execution/runner.rb:37`
- `instance_variable_set` appears only in Lifecycle::Manager, twice: `lib/wild_hook_ops/lifecycle/manager.rb:50`, `lib/wild_hook_ops/lifecycle/manager.rb:58`; AD-006 at `000-docs/003-AT-ADEC-architecture-decisions.md:53-59`
- HookDefinition and HookEvent expose readers only: `lib/wild_hook_ops/models/hook_definition.rb:20-28`, `lib/wild_hook_ops/models/hook_event.rb:9-16`
- Handler ID generation, process-scoped through `object_id`: `lib/wild_hook_ops/models/hook_handler.rb:95-97`; AD-004 at `000-docs/003-AT-ADEC-architecture-decisions.md:33-39`
- `required_permissions` stored as metadata and never read by execution: `lib/wild_hook_ops/models/hook_definition.rb:35`, `lib/wild_hook_ops/registry/hook_registry.rb:19-30`; declared advisory at `000-docs/006-TQ-STND-safety-model.md:28`
- The privileged triggers consumers hang off this gem: `lib/wild_hook_ops/models/hook_definition.rb:11-18`

**Fail closed at the reporting level**

- `on_handler_error: :log_and_continue` default, and the `:halt` alternative: `lib/wild_hook_ops/configuration.rb:21`, `lib/wild_hook_ops/configuration.rb:6`, honoured at `lib/wild_hook_ops/execution/runner.rb:37`
- Undefined hook raises HookNotFoundError: `lib/wild_hook_ops/execution/runner.rb:25`, also at registration `lib/wild_hook_ops/registry/hook_registry.rb:35`; error at `lib/wild_hook_ops/errors.rb:8-12`
- Handler limit raises HandlerLimitExceededError: `lib/wild_hook_ops/registry/handler_store.rb:19-20`; error at `lib/wild_hook_ops/errors.rb:22-26`
- Duplicate definition raises DuplicateHookError: `lib/wild_hook_ops/registry/definition_store.rb:15`; error at `lib/wild_hook_ops/errors.rb:15-19`
- Non-callable rejected with InvalidHandlerError: `lib/wild_hook_ops/models/hook_handler.rb:75-79`; error at `lib/wild_hook_ops/errors.rb:39-43`
- Priority and timeout validated in the constructor, no setters exist: `lib/wild_hook_ops/models/hook_handler.rb:81-93`, reader-only attributes at `lib/wild_hook_ops/models/hook_handler.rb:11-17`
- Config setters validate and raise InvalidConfigurationError: `lib/wild_hook_ops/configuration.rb:25-75`
- Frozen config raises ConfigurationFrozenError: `lib/wild_hook_ops/configuration.rb:88-90`, set by `lib/wild_hook_ops/configuration.rb:77-80`; error at `lib/wild_hook_ops/errors.rb:29-33`

**Scope, artifacts, and the CI gate**

- Gemfile.lock, pkg, coverage, doc, and `*.gem` all gitignored: `.gitignore:5-7`, `.gitignore:10-11`
- Version constant that moves with CHANGELOG.md: `lib/wild_hook_ops/version.rb:4`
- The 000-docs index table this rule refers to: `000-docs/000-INDEX.md:5-12`
- CI is the deterministic gate, rspec and rubocop on 3.2 and 3.3: `.github/workflows/ci.yml:14`, `.github/workflows/ci.yml:25-29`
- RuboCop exclusions that reviewers must not relitigate: `.rubocop.yml:8-10`, `.rubocop.yml:15-18`, `.rubocop.yml:33-41`, `.rubocop.yml:60-67`
- AD-008, parallel accepted by config and unimplemented in Runner: `lib/wild_hook_ops/configuration.rb:5`, `lib/wild_hook_ops/configuration.rb:57-65`, no parallel branch in `lib/wild_hook_ops/execution/runner.rb:30-41`; decision at `000-docs/003-AT-ADEC-architecture-decisions.md:73-79`
- Non-goals the safety model assigns to the consuming application: `000-docs/006-TQ-STND-safety-model.md:27`, `000-docs/006-TQ-STND-safety-model.md:29`
- `spec/adversarial/` exists and is the home for isolation, timeout, and ordering specs: `spec/adversarial/handler_isolation_spec.rb:3-4`
