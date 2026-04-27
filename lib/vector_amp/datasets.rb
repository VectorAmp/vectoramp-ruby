# frozen_string_literal: true

require "securerandom"
require_relative "dataset"
require_relative "utils"

module VectorAmp
  # Dataset API resource for create/list/get/search/insert operations.
  class DatasetsResource
    # @param transport [#request] API transport.
    # @param client [Client, nil] optional client attached to returned Dataset objects.
    # @return [DatasetsResource]
    def initialize(transport, client: nil)
      @transport = transport
      @client = client
    end

    # List datasets.
    # @param limit [Integer] page size; defaults to 50.
    # @param offset [Integer] page offset; defaults to 0.
    # @return [Hash] response envelope with `datasets` wrapped as Dataset objects when present.
    def list(limit: 50, offset: 0)
      wrap_list(@transport.request(:get, "/datasets", query: { limit: limit, offset: offset }))
    end

    # Fetch a dataset by id.
    # @param dataset_id [String] dataset id.
    # @return [Dataset]
    def get(dataset_id)
      wrap_dataset(@transport.request(:get, "/datasets/#{dataset_id}"))
    end

    # Delete a dataset by id.
    # @param dataset_id [String] dataset id.
    # @return [Hash] delete response.
    def delete(dataset_id)
      @transport.request(:delete, "/datasets/#{dataset_id}")
    end

    # Fetch dataset statistics.
    # @param dataset_id [String] dataset id.
    # @return [Hash] stats response.
    def stats(dataset_id)
      @transport.request(:get, "/datasets/#{dataset_id}/stats")
    end

    # Create a SABLE dataset. `index_type` is managed by the SDK and always sent as `sable`.
    # @param name [String] dataset name.
    # @param dim [Integer] embedding/vector dimension.
    # @param embedding [Hash, String] embedding configuration accepted by the API.
    # @param metric [String] distance metric; defaults to `cosine`.
    # @param filters [Hash, nil] optional filter schema/config.
    # @param metadata_schema [Hash, nil] optional metadata schema.
    # @param tuning [Hash, nil] optional SABLE tuning parameters.
    # @return [Dataset] created dataset.
    # @raise [ArgumentError] when `index_type` is supplied or unknown options are passed.
    def create(name:, dim:, embedding:, metric: "cosine", filters: nil, metadata_schema: nil, tuning: nil, **unknown)
      if unknown.key?(:index_type) || unknown.key?("index_type")
        raise ArgumentError, "index_type is managed by VectorAmp Ruby SDK and is always 'sable'"
      end
      Utils.ensure_no_unknown!(unknown, "create")

      body = Utils.compact_hash(
        name: name,
        dim: dim,
        metric: metric,
        embedding: embedding,
        index_type: "sable",
        filters: filters,
        metadata_schema: metadata_schema,
        tuning: tuning
      )
      wrap_dataset(@transport.request(:post, "/datasets", body: body))
    end


    # List retained source documents for a dataset using cursor pagination.
    # @param dataset_id [String] dataset id.
    # @param limit [Integer, nil] maximum documents to return.
    # @param cursor [String, nil] cursor from a previous response's `next_cursor`.
    # @param status [String, nil] optional document status filter, e.g. `ready`.
    # @return [Hash] response envelope with `documents` and `next_cursor`.
    def list_documents(dataset_id, limit: 50, cursor: nil, status: nil)
      @transport.request(:get, "/datasets/#{dataset_id}/documents", query: Utils.compact_hash(limit: limit, cursor: cursor, status: status))
    end

    # Download the retained original bytes for a dataset document.
    # The HTTP transport follows redirects so this returns the final raw object bytes.
    # @param dataset_id [String] dataset id.
    # @param document_id [String] document id returned by {#list_documents}.
    # @return [String] raw document bytes.
    def download_document(dataset_id, document_id)
      @transport.request(:get, "/datasets/#{dataset_id}/documents/#{document_id}/download", raw: true, headers: { Accept: "*/*" })
    end

    # Search a dataset by text or vector query.
    # @param dataset_id [String] dataset id.
    # @param query_text_or_options [String, Hash, nil] text query or legacy options hash.
    # @param query [Array<Numeric>, nil] vector query.
    # @param query_text [String, nil] explicit text query; overrides positional text when provided.
    # @param top_k [Integer] number of results; defaults to 10.
    # @param filters [Hash, nil] metadata filters.
    # @param advanced_filters [Hash, nil] advanced filter expression.
    # @param embedding_model [String, nil] optional embedding model override.
    # @param embedding_provider [String, nil] optional embedding provider override.
    # @param nprobe_override [Integer, nil] optional SABLE search probe override.
    # @param rerank_depth_override [Integer, nil] optional rerank depth override.
    # @param hybrid [Boolean, nil] enable hybrid search when supported.
    # @param sparse_query [Hash, nil] sparse query for hybrid search.
    # @param alpha [Numeric, nil] dense/sparse weighting for hybrid search.
    # @param include_embeddings [Boolean, nil] include vector values in results.
    # @param include_documents [Boolean, nil] include document fields in results.
    # @param include_metadata [Boolean, nil] include metadata; API default is true.
    # @return [Hash] search response.
    def search(dataset_id, query_text_or_options = nil, query: nil, query_text: nil, top_k: 10, filters: nil, advanced_filters: nil,
               embedding_model: nil, embedding_provider: nil, nprobe_override: nil, rerank_depth_override: nil,
               hybrid: nil, sparse_query: nil, alpha: nil, include_embeddings: nil, include_documents: nil,
               include_metadata: nil, **unknown)
      if query_text_or_options.is_a?(Hash)
        unknown = query_text_or_options.merge(unknown)
        query_text_or_options = nil
      end
      Utils.ensure_no_unknown!(unknown, "search")
      resolved_query_text = query_text || query_text_or_options
      body = Utils.compact_hash(
        query: query,
        query_text: resolved_query_text,
        top_k: top_k,
        filters: filters,
        advanced_filters: advanced_filters,
        embedding_model: embedding_model,
        embedding_provider: embedding_provider,
        nprobe_override: nprobe_override,
        rerank_depth_override: rerank_depth_override,
        hybrid: hybrid,
        sparse_query: sparse_query,
        alpha: alpha,
        include_embeddings: include_embeddings,
        include_documents: include_documents,
        include_metadata: include_metadata
      )
      @transport.request(:post, "/datasets/#{dataset_id}/search", body: body)
    end

    # Insert vectors into a dataset.
    # @param dataset_id [String] dataset id.
    # @param vectors [Array<Hash>] vector records with ids, values, and optional metadata.
    # @return [Hash] insert response.
    def insert(dataset_id, vectors:)
      @transport.request(:post, "/datasets/#{dataset_id}/insert", body: { vectors: vectors })
    end

    # Generate embeddings using the dataset embedding configuration.
    # @param dataset_id [String] dataset id.
    # @param text [String, nil] single text to embed.
    # @param texts [Array<String>, nil] multiple texts to embed.
    # @return [Hash] embed response.
    def embed(dataset_id, text: nil, texts: nil)
      raise ArgumentError, "provide text or texts" if text.nil? && texts.nil?

      @transport.request(:post, "/datasets/#{dataset_id}/embed", body: Utils.compact_hash(text: text, texts: texts))
    end

    # Embed and insert texts into a dataset.
    # @param dataset_id [String] dataset id.
    # @param texts_arg [Array<String>, nil] positional texts for convenience.
    # @param texts [Array<String>, nil] keyword texts.
    # @param ids [Array<String>, nil] optional ids; generated UUIDs when omitted.
    # @param metadata [Hash, Array<Hash>, nil] metadata applied to all texts or per-text.
    # @return [Hash] insert response.
    def add_texts(dataset_id, texts_arg = nil, texts: nil, ids: nil, metadata: nil)
      texts ||= texts_arg
      raise ArgumentError, "texts must not be empty" if texts.nil? || texts.empty?
      raise ArgumentError, "ids length must match texts length" if ids && ids.length != texts.length
      if metadata.is_a?(Array) && metadata.length != texts.length
        raise ArgumentError, "metadata length must match texts length"
      end

      response = embed(dataset_id, texts: texts)
      embeddings = response.fetch("embeddings")
      vectors = texts.each_with_index.map do |text, index|
        item_metadata = metadata.is_a?(Array) ? metadata[index] : metadata
        {
          id: ids ? ids[index] : SecureRandom.uuid,
          values: embeddings[index],
          metadata: Utils.compact_hash((item_metadata || {}).merge(text: text))
        }
      end
      insert(dataset_id, vectors: vectors)
    end

    private

    def wrap_dataset(data)
      Dataset.new(data, service: self, client: @client)
    end

    def wrap_list(response)
      return response unless response.is_a?(Hash)

      datasets = response["datasets"] || response[:datasets]
      return response unless datasets.is_a?(Array)

      response.merge("datasets" => datasets.map { |dataset| wrap_dataset(dataset) })
    end
  end
end
