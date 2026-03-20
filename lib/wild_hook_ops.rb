# frozen_string_literal: true

require_relative 'wild_hook_ops/version'
require_relative 'wild_hook_ops/errors'
require_relative 'wild_hook_ops/configuration'

# Models
require_relative 'wild_hook_ops/models/hook_definition'
require_relative 'wild_hook_ops/models/hook_handler'
require_relative 'wild_hook_ops/models/hook_result'
require_relative 'wild_hook_ops/models/hook_event'

# Registry
require_relative 'wild_hook_ops/registry/definition_store'
require_relative 'wild_hook_ops/registry/handler_store'
require_relative 'wild_hook_ops/registry/hook_registry'

# Execution
require_relative 'wild_hook_ops/execution/timeout_guard'
require_relative 'wild_hook_ops/execution/error_isolator'
require_relative 'wild_hook_ops/execution/runner'

# Lifecycle
require_relative 'wild_hook_ops/lifecycle/version_tracker'
require_relative 'wild_hook_ops/lifecycle/manager'

# Health
require_relative 'wild_hook_ops/health/monitor'
require_relative 'wild_hook_ops/health/reporter'

# Audit
require_relative 'wild_hook_ops/audit/trail'
require_relative 'wild_hook_ops/audit/logger'

# WildHookOps is a centralized hook lifecycle management system for agent workflows.
#
# It provides registration, execution, auditing, and health monitoring for
# hook/extension points.
#
# @example Basic usage
#   WildHookOps.configure do |c|
#     c.default_timeout_ms = 3_000
#     c.on_handler_error   = :log_and_continue
#   end
#
#   registry = WildHookOps::Registry::HookRegistry.new
#   registry.define(name: 'before_tool_call', trigger: :before_tool_call)
#   registry.register_handler(hook_name: 'before_tool_call', callable: -> (ctx) { puts ctx.inspect })
#
#   runner = WildHookOps::Execution::Runner.new(registry: registry)
#   results = runner.execute('before_tool_call', { tool: 'bash' })
module WildHookOps
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
