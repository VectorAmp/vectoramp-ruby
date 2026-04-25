# frozen_string_literal: true

module VectorAmp
  # Rich dataset resource returned by DatasetsResource#create/get/list.
  #
  # It keeps the raw API payload while adding convenient instance methods that
  # delegate to the existing service-style APIs.
  class Dataset
    attr_reader :service, :client, :id, :data
    alias raw_data data

    def initialize(data, service:, client: nil)
      @data = normalize_data(data)
      @service = service
      @client = client
      @id = extract_id(@data)
      raise ArgumentError, "dataset id is required" if @id.nil? || @id.to_s.empty?
    end

    def [](key)
      @data[key.to_s]
    end

    def fetch(key, *args, &block)
      @data.fetch(key.to_s, *args, &block)
    end

    def key?(key)
      @data.key?(key.to_s)
    end
    alias has_key? key?

    def to_h
      @data.dup
    end
    alias to_hash to_h

    def inspect
      "#<#{self.class} id=#{id.inspect} data=#{@data.inspect}>"
    end

    def search(**options)
      service.search(id, **options)
    end

    def insert(vectors:)
      service.insert(id, vectors: vectors)
    end

    def add_texts(texts:, ids: nil, metadata: nil)
      service.add_texts(id, texts: texts, ids: ids, metadata: metadata)
    end

    def delete
      service.delete(id)
    end

    def stats
      service.stats(id)
    end

    def ask(query, **options)
      require_client!("ask")
      client.ask(query, **options.merge(dataset_id: id))
    end

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
