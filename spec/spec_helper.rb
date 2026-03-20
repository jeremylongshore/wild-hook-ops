# frozen_string_literal: true

require 'wild_hook_ops'
require_relative 'support/hook_fixtures'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.include WildHookOps::TestSupport::HookFixtures

  config.before do
    WildHookOps.reset_configuration!
  end
end
