# frozen_string_literal: true

require "simplecov"
require "simplecov-cobertura"
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
)
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage 90
end

require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!(
  [
    Minitest::Reporters::DefaultReporter.new(color: true),
    Minitest::Reporters::JUnitReporter.new("test-results", false),
  ]
)
require "webmock/minitest"
require "vector_amp"

WebMock.disable_net_connect!(allow_localhost: true)
