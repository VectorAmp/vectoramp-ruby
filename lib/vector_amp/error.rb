# frozen_string_literal: true

module VectorAmp
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class APIError < Error
    attr_reader :status, :body, :headers

    def initialize(message, status: nil, body: nil, headers: {})
      super(message)
      @status = status
      @body = body
      @headers = headers
    end
  end
end
