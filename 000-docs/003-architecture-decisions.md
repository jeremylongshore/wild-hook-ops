# 003 — Architecture Decisions: wild-hook-ops

## AD-001: No external dependencies

**Decision:** Depend only on Ruby stdlib (Timeout).

**Rationale:** Hook-ops is a foundational library intended to be embedded in other wild-* repos. Minimizing dependencies reduces version conflicts, install surface, and audit burden.

**Consequence:** No ActiveSupport, no concurrent-ruby. Thread safety is handled manually with Mutex. Timeout is handled with stdlib Timeout.

---

## AD-002: Constructor injection for all external collaborators

**Decision:** Runner, Logger, and Reporter accept registry, config, audit_logger, health_monitor as constructor parameters.

**Rationale:** Makes every component independently testable without global state. Consumers wire up the graph themselves.

**Consequence:** More verbose construction at callsite, but explicitly testable without mocking global state.

---

## AD-003: Audit trail as a capped ring buffer

**Decision:** Trail uses a simple Array with shift-on-overflow when max_audit_entries is reached.

**Rationale:** In-memory with no external storage. The ring buffer prevents unbounded memory growth. Evicts oldest entries first (FIFO).

**Consequence:** Long-running processes lose old audit history. If durability is needed, consumers should drain the trail periodically.

---

## AD-004: Handler IDs are process-scoped strings

**Decision:** HookHandler#id is generated as `"handler_#{hook_name}_#{object_id}_#{registered_at.to_i}"`.

**Rationale:** Unique within a process for the lifetime of the handler. Deterministic enough for audit trail correlation and health metrics keying.

**Consequence:** IDs are not stable across restarts or serializable across processes. Not intended for persistence.

---

## AD-005: ErrorIsolator does not rescue Timeout::Error or SignalException

**Decision:** ErrorIsolator rescues StandardError but explicitly re-raises Timeout::Error and Interrupt.

**Rationale:** Timeout::Error is raised by TimeoutGuard and must propagate to it for correct :timeout outcome recording. SignalException (Interrupt, SIGTERM, etc.) must propagate to allow graceful process shutdown.

**Consequence:** Only StandardError subclasses are isolated. This is the correct semantics for handler sandboxing.

---

## AD-006: HookDefinition and HookEvent are value-like objects

**Decision:** HookDefinition and HookEvent store all data in instance variables set at construction. They do not expose setters (except via instance_variable_set used deliberately by Lifecycle::Manager).

**Rationale:** Treating definitions as immutable prevents accidental mutation. Lifecycle::Manager uses instance_variable_set as a deliberate privileged operation — this is intentional, not a workaround.

**Consequence:** The lifecycle operations are explicit. Nothing can accidentally change a definition's version or deprecated flag without going through Manager.

---

## AD-007: Metrics Struct is mutable inside Monitor

**Decision:** Monitor::Metrics is a Struct with mutable numeric fields, mutated inside a synchronized block.

**Rationale:** Struct provides named field access and easy to_h. Mutation inside Mutex.synchronize is safe and avoids allocating new objects on every call.

**Consequence:** Metrics objects should not be held outside the monitor without understanding they may be mutated. The public interface returns dup'd data where needed.

---

## AD-008: Parallel execution mode is reserved, not implemented

**Decision:** Configuration accepts `:parallel` as a valid execution_mode, but Runner always executes sequentially.

**Rationale:** The interface is forward-declared so consumers can configure it, but the complexity of thread-per-handler execution with proper error collection is deferred until there is a concrete use case.

**Consequence:** Setting `execution_mode: :parallel` currently has no effect on Runner behavior.
