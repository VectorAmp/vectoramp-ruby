# frozen_string_literal: true

require_relative "datasets"
require_relative "error"
require_relative "ingestion"
require_relative "intelligence"
require_relative "source"
require_relative "transport/http"

module VectorAmp
  # Top-level API client for VectorAmp datasets, ingestion sources/jobs, and intelligence.
  class Client
    DEFAULT_BASE_URL = "https://api.vectoramp.com"

    # @return [String] API base URL used by this client.
    # @return [DatasetsResource] dataset API resource.
    # @return [IngestionResource] ingestion/source API resource.
    # @return [IntelligenceResource] intelligence API resource.
    attr_reader :base_url, :datasets, :ingestion, :intelligence, :sources

    # Create a VectorAmp API client.
    # @param api_key [String] API key; defaults to ENV["VECTORAMP_API_KEY"].
    # @param base_url [String] API base URL; defaults to the production API.
    # @param transport [#request, nil] optional custom transport for tests or advanced use.
    # @param timeout [Numeric] HTTP timeout in seconds for the default transport.
    # @return [Client]
    # @raise [ConfigurationError] when api_key is missing.
    def initialize(api_key: ENV["VECTORAMP_API_KEY"], base_url: DEFAULT_BASE_URL, transport: nil, timeout: Transport::HTTP::DEFAULT_TIMEOUT)
      raise ConfigurationError, "api_key is required" if api_key.nil? || api_key.empty?

      @base_url = base_url
      @transport = transport || Transport::HTTP.new(base_url: base_url, api_key: api_key, timeout: timeout)
      @ingestion = IngestionResource.new(@transport)
      @sources = @ingestion
      @intelligence = IntelligenceResource.new(@transport)
      @datasets = DatasetsResource.new(@transport, client: self)
    end

    # Ask an intelligence question and return a complete response.
    # @param query [String] natural-language question.
    # @param options [Hash] forwarded to {IntelligenceResource#query}; `stream` is forced to false.
    # @return [Hash] intelligence response.
    def ask(query, **options)
      @intelligence.query(query, **options.merge(stream: false))
    end

    # Ask an intelligence question as a stream.
    # @param query [String] natural-language question.
    # @param options [Hash] forwarded to {IntelligenceResource#query}; `stream` is forced to true.
    # @yieldparam chunk [Object] streamed response chunk from the transport.
    # @return [Enumerator, Object] enumerator without a block, otherwise the transport result.
    def ask_stream(query, **options, &block)
      @intelligence.query(query, **options.merge(stream: true), &block)
    end
  end
end
