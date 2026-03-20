# frozen_string_literal: true

require_relative 'lib/wild_hook_ops/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-hook-ops'
  spec.version = WildHookOps::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Centralized hook lifecycle management for agent workflows'
  spec.description = 'Registration, execution, auditing, and health monitoring for hook/extension ' \
                     'points in agent workflows. Provides priority-ordered execution with timeouts, ' \
                     'error isolation, audit trails, and per-handler health metrics.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-hook-ops'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
