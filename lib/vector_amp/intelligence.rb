# frozen_string_literal: true

require_relative "utils"

module VectorAmp
  # Intelligence API resource for retrieval-augmented question answering.
  class IntelligenceResource
    # @param transport [#request] API transport.
    # @return [IntelligenceResource]
    def initialize(transport)
      @transport = transport
    end

    # Ask an intelligence query, optionally scoped to a dataset and streamed.
    # @param query [String] natural-language question.
    # @param dataset_id [String, nil] optional dataset id scope.
    # @param top_k [Integer, nil] optional retrieval result count.
    # @param conversation_history [Array<Hash>, nil] optional prior conversation messages.
    # @param include_sources [Boolean, nil] include source chunks/citations when supported.
    # @param stream [Boolean] stream chunks when true; defaults to false.
    # @yieldparam chunk [Object] streamed response chunk when stream is true.
    # @return [Hash, Enumerator, Object] response hash, enumerator without a stream block, or transport stream result.
    def query(query, dataset_id: nil, top_k: nil, conversation_history: nil, include_sources: nil, stream: false, **unknown, &block)
      Utils.ensure_no_unknown!(unknown, "query")
      body = Utils.compact_hash(
        query: query,
        dataset_id: dataset_id,
        top_k: top_k,
        conversation_history: conversation_history,
        include_sources: include_sources,
        stream: stream
      )

      if stream
        return enum_for(:query, query, dataset_id: dataset_id, top_k: top_k,
                        conversation_history: conversation_history, include_sources: include_sources,
                        stream: true) unless block

        @transport.request(:post, "/intelligence/query", body: body, stream: true, &block)
      else
        @transport.request(:post, "/intelligence/query", body: body)
      end
    end
  end
end
