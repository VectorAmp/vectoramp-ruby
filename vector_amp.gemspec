# frozen_string_literal: true

require_relative "lib/vector_amp/version"

Gem::Specification.new do |spec|
  spec.name = "vector_amp"
  spec.version = VectorAmp::VERSION
  spec.authors = ["VectorAmp"]
  spec.email = ["support@vectoramp.com"]

  spec.summary = "Ruby SDK for the VectorAmp API"
  spec.description = "Official Ruby client for VectorAmp datasets, ingestion, and intelligence APIs."
  spec.homepage = "https://vectoramp.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://gitlab.com/VectorAmp/SDK/Ruby"
  spec.metadata["changelog_uri"] = "https://gitlab.com/VectorAmp/SDK/Ruby/-/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "minitest-reporters", "~> 1.7"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "simplecov-cobertura", "~> 2.1"
  spec.add_development_dependency "webmock", "~> 3.25"
end
