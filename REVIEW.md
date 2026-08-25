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
   `inspect`s every key and value of the caller's context hash into `HookEvent#context_summary`, and
   the raw `error.message` into `error_message`. The only containment is
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

- **Zero runtime dependencies.** Ruby stdlib only (`timeout`, `set`). Anything added to the
  gemspec's runtime dependencies violates AD-001, and suggesting ActiveSupport or concurrent-ruby is
  not a review comment, it is a rejected decision.
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
- A callable that does not respond to `#call` is rejected at registration, and an invalid
  `priority`, `timeout_ms`, or config value raises at the setter. Validation moves earlier, never
  later.
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
