# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage 90
end

require "minitest/autorun"
require "webmock/minitest"
require "vector_amp"

WebMock.disable_net_connect!(allow_localhost: true)
