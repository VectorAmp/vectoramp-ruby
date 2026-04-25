# frozen_string_literal: true

require "securerandom"
require_relative "utils"

module VectorAmp
  class DatasetsResource
    def initialize(transport)
      @transport = transport
    end

    def list(limit: 50, offset: 0)
      @transport.request(:get, "/datasets", query: { limit: limit, offset: offset })
    end

    def get(dataset_id)
      @transport.request(:get, "/datasets/#{dataset_id}")
    end

    def delete(dataset_id)
      @transport.request(:delete, "/datasets/#{dataset_id}")
    end

    def stats(dataset_id)
      @transport.request(:get, "/datasets/#{dataset_id}/stats")
    end

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
      @transport.request(:post, "/datasets", body: body)
    end

    def search(dataset_id, query: nil, query_text: nil, top_k: 10, filters: nil, advanced_filters: nil,
               embedding_model: nil, embedding_provider: nil, nprobe_override: nil, rerank_depth_override: nil,
               hybrid: nil, sparse_query: nil, alpha: nil, include_embeddings: nil, include_documents: nil,
               include_metadata: nil, **unknown)
      Utils.ensure_no_unknown!(unknown, "search")
      body = Utils.compact_hash(
        query: query,
        query_text: query_text,
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

    def insert(dataset_id, vectors:)
      @transport.request(:post, "/datasets/#{dataset_id}/insert", body: { vectors: vectors })
    end

    def embed(dataset_id, text: nil, texts: nil)
      raise ArgumentError, "provide text or texts" if text.nil? && texts.nil?

      @transport.request(:post, "/datasets/#{dataset_id}/embed", body: Utils.compact_hash(text: text, texts: texts))
    end

    def add_texts(dataset_id, texts:, ids: nil, metadata: nil)
      raise ArgumentError, "texts must not be empty" if texts.empty?
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
  end
end
