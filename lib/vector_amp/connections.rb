# frozen_string_literal: true

require_relative "utils"

module VectorAmp
  # Managed OAuth/credential connections used by ingestion sources.
  #
  # Connections live at the gateway root (`/connections`), not under
  # `/ingestion`. A connection captures a provider authorization (e.g. Google
  # Drive, Confluence) that ingestion sources can then reference via
  # `connection_id` instead of embedding raw credentials.
  class ConnectionsResource
    # @param transport [#request] API transport.
    # @return [ConnectionsResource]
    def initialize(transport)
      @transport = transport
    end

    # List connections, optionally filtered by provider.
    # @param provider [String, nil] optional provider filter (e.g. `google_drive`, `confluence`).
    # @return [Hash] response envelope with `connections`.
    def list(provider: nil)
      @transport.request(:get, "/connections", query: Utils.compact_hash(provider: provider))
    end

    # Create a connection and begin the provider authorization flow.
    # @param provider [String] provider identifier (e.g. `google_drive`, `confluence`).
    # @param source_type [String, nil] optional source type the connection will be used with.
    # @return [Hash] created connection with `id`, `provider`, `status`, and `authorization_url`.
    def create(provider, source_type: nil)
      body = Utils.compact_hash(provider: provider, source_type: source_type)
      @transport.request(:post, "/connections", body: body)
    end

    # Fetch a connection.
    # @param connection_id [String] connection id.
    # @return [Hash] connection resource.
    def get(connection_id)
      @transport.request(:get, "/connections/#{connection_id}")
    end

    # Delete a connection.
    # @param connection_id [String] connection id.
    # @return [Hash] delete response.
    def delete(connection_id)
      @transport.request(:delete, "/connections/#{connection_id}")
    end
  end
end
