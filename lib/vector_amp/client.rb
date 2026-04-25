# frozen_string_literal: true

require_relative "datasets"
require_relative "error"
require_relative "ingestion"
require_relative "intelligence"
require_relative "transport/http"

module VectorAmp
  class Client
    DEFAULT_BASE_URL = "https://api.vectoramp.com"

    attr_reader :base_url, :datasets, :ingestion, :intelligence

    def initialize(api_key: ENV["VECTORAMP_API_KEY"], base_url: DEFAULT_BASE_URL, transport: nil, timeout: Transport::HTTP::DEFAULT_TIMEOUT)
      raise ConfigurationError, "api_key is required" if api_key.nil? || api_key.empty?

      @base_url = base_url
      @transport = transport || Transport::HTTP.new(base_url: base_url, api_key: api_key, timeout: timeout)
      @ingestion = IngestionResource.new(@transport)
      @intelligence = IntelligenceResource.new(@transport)
      @datasets = DatasetsResource.new(@transport, client: self)
    end

    def ask(query, **options)
      @intelligence.query(query, **options.merge(stream: false))
    end

    def ask_stream(query, **options, &block)
      @intelligence.query(query, **options.merge(stream: true), &block)
    end
  end
end
