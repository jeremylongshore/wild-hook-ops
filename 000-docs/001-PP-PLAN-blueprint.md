# 001 — Blueprint: wild-hook-ops

## Mission

Provide a centralized, tested, and auditable hook lifecycle management library for the wild ecosystem. Any wild-* tool that needs before/after extension points (before_tool_call, on_capability_check, etc.) uses this library instead of reinventing its own.

## Problem Statement

wild-admin-tools-mcp emits hooks at 3 points. wild-rails-safe-introspection-mcp emits hooks at 3 points. Each invented its own HookEmitter class independently. When the pattern diverges or a bug is found, it must be fixed in N places.

Hook-ops solves this by being the single implementation.

## Boundaries

**In scope:**
- Hook definition registration and storage
- Handler registration with priority, timeout, and enable/disable
- Priority-ordered execution with per-handler timeout enforcement
- Error isolation: catch StandardError, record :error, optionally halt
- Audit trail: HookEvent records in a capped ring buffer
- Health metrics: per-handler call counts, error rates, avg duration
- Lifecycle: deprecate hooks, enable/disable handlers, version tracking
- Thread safety on all mutable stores

**Out of scope:**
- Persistent storage (no database, no file I/O)
- Parallel execution (config option reserved for future)
- Network-based hook dispatch
- Authentication/authorization of handler registration
- Web framework integration
- HTTP or MCP server

## Non-Goals

- This is NOT about Claude Code settings.json hooks
- This does NOT replace wild-capability-gate (permissions are advisory here)
- This does NOT provide retry logic for failed handlers
- This does NOT guarantee handler ordering across processes

## Design Principles

1. **No external dependencies** — stdlib only (Timeout)
2. **Thread safety by default** — all stores use Mutex
3. **Error isolation always** — one bad handler never crashes the chain
4. **Audit by default** — everything is recorded unless explicitly disabled
5. **Composable** — registry, runner, audit, and health are independent; wire them as needed
6. **Testable** — every component accepts its dependencies via constructor injection
