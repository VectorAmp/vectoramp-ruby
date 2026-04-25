# frozen_string_literal: true

require_relative "utils"

module VectorAmp
  class IntelligenceResource
    def initialize(transport)
      @transport = transport
    end

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
