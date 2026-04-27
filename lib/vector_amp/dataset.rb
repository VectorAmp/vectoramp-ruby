# frozen_string_literal: true

module VectorAmp
  # Rich dataset resource returned by DatasetsResource#create/get/list.
  #
  # It keeps the raw API payload while adding convenient instance methods that
  # delegate to the existing service-style APIs.
  class Dataset
    # @return [DatasetsResource] backing dataset service.
    # @return [Client, nil] client that created this object, required for convenience ingestion/ask helpers.
    # @return [String] dataset id.
    # @return [Hash] normalized raw API payload.
    attr_reader :service, :client, :id, :data
    alias raw_data data

    # @param data [Hash] dataset API payload; `id` or `dataset_id` is required.
    # @param service [DatasetsResource] backing dataset service.
    # @param client [Client, nil] optional client for convenience helpers.
    # @return [Dataset]
    def initialize(data, service:, client: nil)
      @data = normalize_data(data)
      @service = service
      @client = client
      @id = extract_id(@data)
      raise ArgumentError, "dataset id is required" if @id.nil? || @id.to_s.empty?
    end

    # Read a raw dataset field by string or symbol key.
    # @param key [String, Symbol] field name.
    # @return [Object, nil]
    def [](key)
      @data[key.to_s]
    end

    # Fetch a raw dataset field by string or symbol key.
    # @param key [String, Symbol] field name.
    # @return [Object]
    def fetch(key, *args, &block)
      @data.fetch(key.to_s, *args, &block)
    end

    # @param key [String, Symbol] field name.
    # @return [Boolean] whether the raw payload has the field.
    def key?(key)
      @data.key?(key.to_s)
    end
    alias has_key? key?

    # @return [Hash] shallow copy of the raw API payload.
    def to_h
      @data.dup
    end
    alias to_hash to_h

    def inspect
      "#<#{self.class} id=#{id.inspect} data=#{@data.inspect}>"
    end

    # Search this dataset.
    # @param query_text [String, nil] optional text query; alternatively pass `query:` vector/options.
    # @param options [Hash] forwarded to {DatasetsResource#search}.
    # @return [Hash] search response.
    def search(query_text = nil, **options)
      service.search(id, query_text, **options)
    end

    # Insert vectors into this dataset.
    # @param vectors [Array<Hash>] vector records with ids, values, and optional metadata.
    # @return [Hash] insert response.
    def insert(vectors:)
      service.insert(id, vectors: vectors)
    end

    # Embed and insert texts into this dataset.
    # @param texts_arg [Array<String>, nil] positional texts for convenience.
    # @param texts [Array<String>, nil] keyword texts.
    # @param ids [Array<String>, nil] optional ids; generated UUIDs when omitted.
    # @param metadata [Hash, Array<Hash>, nil] metadata applied to all texts or per-text.
    # @return [Hash] insert response.
    def add_texts(texts_arg = nil, texts: nil, ids: nil, metadata: nil)
      service.add_texts(id, texts_arg, texts: texts, ids: ids, metadata: metadata)
    end

    # Delete this dataset.
    # @return [Hash] delete response.
    def delete
      service.delete(id)
    end

    # Fetch stats for this dataset.
    # @return [Hash] dataset statistics.
    def stats
      service.stats(id)
    end


    # List retained source documents for this dataset using cursor pagination.
    # @param limit [Integer, nil] maximum documents to return.
    # @param cursor [String, nil] cursor from a previous response's `next_cursor`.
    # @param status [String, nil] optional document status filter.
    # @return [Hash] response envelope with `documents` and `next_cursor`.
    def list_documents(limit: 50, cursor: nil, status: nil)
      service.list_documents(id, limit: limit, cursor: cursor, status: status)
    end

    # Download retained original bytes for a dataset source document.
    # @param document_id [String] document id returned by {#list_documents}.
    # @return [String] raw document bytes.
    def download_document(document_id)
      service.download_document(id, document_id)
    end

    # Ask an intelligence question constrained to this dataset.
    # @param query [String] natural-language question.
    # @param options [Hash] forwarded to {Client#ask}; `dataset_id` is set to this dataset id.
    # @return [Hash] intelligence response.
    def ask(query, **options)
      require_client!("ask")
      client.ask(query, **options.merge(dataset_id: id))
    end

    # Upload local files by auto-creating a `file_upload` source, initializing presigned uploads, and completing the upload job.
    # @param paths [String, Array<String>] local file paths to upload.
    # @param source_name [String, nil] optional source name; defaults to timestamped Ruby SDK file-upload name.
    # @param description [String, nil] optional source description.
    # @param metadata [Hash] optional source metadata; dataset_id is added automatically.
    # @return [Hash] upload completion/job response.
    def ingest_files(paths:, source_name: nil, description: nil, metadata: {})
      require_client!("ingest_files")
      client.ingestion.ingest_files(
        dataset_id: id,
        paths: paths,
        source_name: source_name,
        description: description,
        metadata: metadata
      )
    end

    # Start an ingestion job from an existing source into this dataset.
    # @param source_id [String, Source, Hash, nil] source id or object/hash containing an id.
    # @param source [Source, Hash, nil] alternate source object/hash containing an id.
    # @param pipeline_id [String, nil] optional pipeline id.
    # @return [Hash] ingestion job response.
    def ingest_source(source_id = nil, source: nil, pipeline_id: nil)
      require_client!("ingest_source")
      resolved_source_id = extract_source_id(source_id || source)
      raise ArgumentError, "source_id is required" if resolved_source_id.nil? || resolved_source_id.to_s.empty?

      client.ingestion.start_job(source_id: resolved_source_id, dataset_id: id, pipeline_id: pipeline_id)
    end

    private

    def normalize_data(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = item }
      else
        {}
      end
    end

    def extract_id(hash)
      return nil unless hash

      hash["id"] || hash[:id] || hash["dataset_id"] || hash[:dataset_id]
    end

    def extract_source_id(value)
      return value if value.is_a?(String) || value.is_a?(Symbol)
      return value.id if value.respond_to?(:id)

      extract_id(normalize_data(value))
    end

    def require_client!(method_name)
      return if client

      raise ArgumentError, "#{method_name} requires a Dataset created by VectorAmp::Client"
    end
  end
end
