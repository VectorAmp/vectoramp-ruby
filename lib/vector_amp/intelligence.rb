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

    # Create an intelligence conversation session.
    # @param title [String, nil] optional session title.
    # @param dataset_id [String, nil] optional dataset scope.
    # @param workspace_id [String, nil] optional workspace id.
    # @param metadata [Hash, nil] optional session metadata.
    # @return [Hash] created session.
    def create_session(title: nil, dataset_id: nil, workspace_id: nil, metadata: nil)
      body = Utils.compact_hash(
        title: title,
        dataset_id: dataset_id,
        workspace_id: workspace_id,
        metadata: metadata
      )
      @transport.request(:post, "/intelligence/sessions", body: body)
    end

    # List intelligence sessions.
    # @param limit [Integer] page size; defaults to 50.
    # @return [Hash] response envelope with `sessions`.
    def list_sessions(limit: 50)
      @transport.request(:get, "/intelligence/sessions", query: { limit: limit })
    end

    # Fetch an intelligence session.
    # @param session_id [String] session id.
    # @return [Hash] session resource.
    def get_session(session_id)
      @transport.request(:get, "/intelligence/sessions/#{session_id}")
    end

    # Delete an intelligence session.
    # @param session_id [String] session id.
    # @return [Hash] delete response.
    def delete_session(session_id)
      @transport.request(:delete, "/intelligence/sessions/#{session_id}")
    end

    # Append a message to a session.
    # @param session_id [String] session id.
    # @param role [String] message role: `user`, `assistant`, `system`, or `tool`.
    # @param content [String] message content.
    # @param metadata [Hash, nil] optional message metadata.
    # @return [Hash] created message.
    def append_message(session_id, role:, content:, metadata: nil)
      body = Utils.compact_hash(role: role, content: content, metadata: metadata)
      @transport.request(:post, "/intelligence/sessions/#{session_id}/messages", body: body)
    end

    # List messages in a session.
    # @param session_id [String] session id.
    # @param limit [Integer] page size; defaults to 100.
    # @return [Hash] response envelope with `messages`.
    def list_messages(session_id, limit: 100)
      @transport.request(:get, "/intelligence/sessions/#{session_id}/messages", query: { limit: limit })
    end
  end
end
