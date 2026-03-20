# frozen_string_literal: true

RSpec.describe WildHookOps::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'has default_timeout_ms of 5_000' do
      expect(config.default_timeout_ms).to eq(5_000)
    end

    it 'has max_handlers_per_hook of 20' do
      expect(config.max_handlers_per_hook).to eq(20)
    end

    it 'enables audit logging by default' do
      expect(config.enable_audit_logging).to be true
    end

    it 'has max_audit_entries of 10_000' do
      expect(config.max_audit_entries).to eq(10_000)
    end

    it 'has execution_mode :sequential' do
      expect(config.execution_mode).to eq(:sequential)
    end

    it 'has on_handler_error :log_and_continue' do
      expect(config.on_handler_error).to eq(:log_and_continue)
    end

    it 'is not frozen by default' do
      expect(config.frozen?).to be false
    end
  end

  describe '#default_timeout_ms=' do
    it 'accepts a positive integer' do
      config.default_timeout_ms = 2_000
      expect(config.default_timeout_ms).to eq(2_000)
    end

    it 'rejects zero' do
      expect { config.default_timeout_ms = 0 }.to raise_error(WildHookOps::InvalidConfigurationError)
    end

    it 'rejects a string' do
      expect { config.default_timeout_ms = '5000' }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#max_handlers_per_hook=' do
    it 'accepts a positive integer' do
      config.max_handlers_per_hook = 50
      expect(config.max_handlers_per_hook).to eq(50)
    end

    it 'rejects negative values' do
      expect { config.max_handlers_per_hook = -1 }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#enable_audit_logging=' do
    it 'accepts false' do
      config.enable_audit_logging = false
      expect(config.enable_audit_logging).to be false
    end

    it 'rejects non-boolean' do
      expect { config.enable_audit_logging = 'yes' }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#max_audit_entries=' do
    it 'accepts a positive integer' do
      config.max_audit_entries = 500
      expect(config.max_audit_entries).to eq(500)
    end

    it 'rejects zero' do
      expect { config.max_audit_entries = 0 }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#execution_mode=' do
    it 'accepts :sequential' do
      config.execution_mode = :sequential
      expect(config.execution_mode).to eq(:sequential)
    end

    it 'accepts :parallel' do
      config.execution_mode = :parallel
      expect(config.execution_mode).to eq(:parallel)
    end

    it 'rejects unknown modes' do
      expect { config.execution_mode = :batched }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#on_handler_error=' do
    it 'accepts :halt' do
      config.on_handler_error = :halt
      expect(config.on_handler_error).to eq(:halt)
    end

    it 'rejects unknown modes' do
      expect { config.on_handler_error = :explode }.to raise_error(WildHookOps::InvalidConfigurationError)
    end
  end

  describe '#freeze!' do
    it 'returns self' do
      expect(config.freeze!).to be config
    end

    it 'marks config as frozen' do
      config.freeze!
      expect(config.frozen?).to be true
    end

    it 'prevents mutations after freeze' do
      config.freeze!
      expect { config.default_timeout_ms = 100 }
        .to raise_error(WildHookOps::ConfigurationFrozenError)
    end

    it 'prevents all setter mutations after freeze' do
      config.freeze!
      %i[max_handlers_per_hook enable_audit_logging max_audit_entries execution_mode
         on_handler_error].each do |attr|
        expect { config.public_send(:"#{attr}=", config.public_send(attr)) }
          .to raise_error(WildHookOps::ConfigurationFrozenError)
      end
    end
  end

  describe 'WildHookOps module helpers' do
    it 'provides .configuration' do
      expect(WildHookOps.configuration).to be_a(described_class)
    end

    it '.configure yields configuration' do
      WildHookOps.configure { |c| c.default_timeout_ms = 1_000 }
      expect(WildHookOps.configuration.default_timeout_ms).to eq(1_000)
    end

    it '.reset_configuration! returns a fresh config' do
      WildHookOps.configure { |c| c.default_timeout_ms = 999 }
      WildHookOps.reset_configuration!
      expect(WildHookOps.configuration.default_timeout_ms).to eq(5_000)
    end
  end
end
