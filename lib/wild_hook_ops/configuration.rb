# frozen_string_literal: true

module WildHookOps
  class Configuration
    VALID_EXECUTION_MODES = %i[sequential parallel].freeze
    VALID_ERROR_MODES = %i[log_and_continue halt].freeze

    attr_reader :default_timeout_ms,
                :max_handlers_per_hook,
                :enable_audit_logging,
                :max_audit_entries,
                :execution_mode,
                :on_handler_error

    def initialize
      @default_timeout_ms     = 5_000
      @max_handlers_per_hook  = 20
      @enable_audit_logging   = true
      @max_audit_entries      = 10_000
      @execution_mode         = :sequential
      @on_handler_error       = :log_and_continue
      @frozen                 = false
    end

    def default_timeout_ms=(value)
      guard_frozen!
      raise InvalidConfigurationError, 'default_timeout_ms must be a positive Integer' \
        unless value.is_a?(Integer) && value.positive?

      @default_timeout_ms = value
    end

    def max_handlers_per_hook=(value)
      guard_frozen!
      raise InvalidConfigurationError, 'max_handlers_per_hook must be a positive Integer' \
        unless value.is_a?(Integer) && value.positive?

      @max_handlers_per_hook = value
    end

    def enable_audit_logging=(value)
      guard_frozen!
      raise InvalidConfigurationError, 'enable_audit_logging must be a Boolean' \
        unless [true, false].include?(value)

      @enable_audit_logging = value
    end

    def max_audit_entries=(value)
      guard_frozen!
      raise InvalidConfigurationError, 'max_audit_entries must be a positive Integer' \
        unless value.is_a?(Integer) && value.positive?

      @max_audit_entries = value
    end

    def execution_mode=(value)
      guard_frozen!
      unless VALID_EXECUTION_MODES.include?(value)
        raise InvalidConfigurationError,
              "execution_mode must be one of #{VALID_EXECUTION_MODES.inspect}"
      end

      @execution_mode = value
    end

    def on_handler_error=(value)
      guard_frozen!
      unless VALID_ERROR_MODES.include?(value)
        raise InvalidConfigurationError,
              "on_handler_error must be one of #{VALID_ERROR_MODES.inspect}"
      end

      @on_handler_error = value
    end

    def freeze!
      @frozen = true
      self
    end

    def frozen?
      @frozen
    end

    private

    def guard_frozen!
      raise ConfigurationFrozenError if @frozen
    end
  end
end
