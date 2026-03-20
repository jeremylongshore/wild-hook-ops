# frozen_string_literal: true

module WildHookOps
  # Base error for all WildHookOps exceptions.
  class Error < StandardError; end

  # Raised when a hook definition with the given name is not found.
  class HookNotFoundError < Error
    def initialize(hook_name)
      super("Hook definition not found: #{hook_name.inspect}")
    end
  end

  # Raised when attempting to register a duplicate hook definition.
  class DuplicateHookError < Error
    def initialize(hook_name)
      super("Hook definition already registered: #{hook_name.inspect}")
    end
  end

  # Raised when the handler store has reached max_handlers_per_hook.
  class HandlerLimitExceededError < Error
    def initialize(hook_name, limit)
      super("Handler limit (#{limit}) exceeded for hook: #{hook_name.inspect}")
    end
  end

  # Raised when configuration has been frozen and a mutation is attempted.
  class ConfigurationFrozenError < Error
    def initialize
      super('WildHookOps configuration is frozen and cannot be modified')
    end
  end

  # Raised when configuration values are invalid.
  class InvalidConfigurationError < Error; end

  # Raised when a handler callable is not valid.
  class InvalidHandlerError < Error
    def initialize(msg = 'Handler must respond to #call')
      super
    end
  end
end
