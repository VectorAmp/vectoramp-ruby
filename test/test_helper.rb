# frozen_string_literal: true

require "fileutils"
require "simplecov"
require "simplecov-cobertura"

FileUtils.mkdir_p("test-results")
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
)
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage line: 90, branch: 60
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
