# frozen_string_literal: true

require "uri"
require_relative "utils"

module VectorAmp
  # Base value object for ingestion source definitions.
  #
  # Source objects can be passed to `client.sources.create_source(source)` to
  # create a source or to `dataset.ingest_source(source)` once they include an id
  # returned by the API.
  class Source
    SUPPORTED_SOURCE_TYPES = %w[s3 web gdrive file_upload].freeze

    attr_reader :id, :source_type, :name, :description, :config, :metadata

    def initialize(source_type:, name:, config:, description: nil, metadata: nil, id: nil)
      raise ArgumentError, "source_type is required" if source_type.nil? || source_type.to_s.empty?
      raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
      raise ArgumentError, "config must be a Hash" unless config.is_a?(Hash)

      @id = id
      @source_type = source_type.to_s
      @name = name.to_s
      @description = description
      @config = config
      @metadata = metadata
    end

    def self.from_api(data)
      hash = normalize_hash(data)
      GenericSource.new(
        id: hash["id"],
        source_type: hash.fetch("source_type"),
        name: hash.fetch("name"),
        description: hash["description"],
        config: hash.fetch("config", {}),
        metadata: hash["metadata"]
      )
    end

    def [](key)
      to_h[key.to_sym] || to_h[key.to_s]
    end

    def to_h
      Utils.compact_hash(
        id: id,
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
    end
    alias to_hash to_h

    def to_create_body
      Utils.compact_hash(
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
    end

    def inspect
      "#<#{self.class} id=#{id.inspect} source_type=#{source_type.inspect} name=#{name.inspect}>"
    end

    def self.normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = item }
      else
        {}
      end
    end
  end

  module SourceNames
    module_function

    def file_upload(now: Time.now.utc)
      "ruby-sdk-file-upload-#{now.strftime("%Y%m%d%H%M%S")}"
    end

    def web(start_urls)
      first_url = Array(start_urls).first.to_s
      host = URI.parse(first_url).host
      host && !host.empty? ? "web-#{host}" : "web-source"
    rescue URI::InvalidURIError
      "web-source"
    end

    def s3(bucket, prefix = nil)
      parts = ["s3", bucket.to_s, prefix.to_s.delete_suffix("/")].reject(&:empty?)
      parts.join("-")
    end

    def google_drive(folder_ids: nil, file_ids: nil)
      first_folder = Array(folder_ids).first
      first_file = Array(file_ids).first
      suffix = first_folder || first_file
      suffix ? "google-drive-#{suffix}" : "google-drive-source"
    end
  end

  class WebSource < Source
    def initialize(start_urls:, name: nil, description: nil, metadata: nil, id: nil, **config)
      urls = Array(start_urls)
      raise ArgumentError, "start_urls must not be empty" if urls.empty?

      super(
        id: id,
        source_type: "web",
        name: name || SourceNames.web(urls),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(start_urls: urls))
      )
    end
  end

  class S3Source < Source
    def initialize(bucket:, name: nil, prefix: nil, description: nil, metadata: nil, id: nil, **config)
      raise ArgumentError, "bucket is required" if bucket.nil? || bucket.to_s.empty?

      super(
        id: id,
        source_type: "s3",
        name: name || SourceNames.s3(bucket, prefix),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(bucket: bucket, prefix: prefix))
      )
    end
  end

  class GoogleDriveSource < Source
    def initialize(name: nil, folder_ids: nil, file_ids: nil, description: nil, metadata: nil, id: nil, **config)
      if Array(folder_ids).empty? && Array(file_ids).empty?
        raise ArgumentError, "folder_ids or file_ids is required"
      end

      super(
        id: id,
        source_type: "gdrive",
        name: name || SourceNames.google_drive(folder_ids: folder_ids, file_ids: file_ids),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(folder_ids: folder_ids, file_ids: file_ids))
      )
    end
  end

  class FileUploadSource < Source
    def initialize(name: nil, description: nil, metadata: nil, id: nil, storage_provider: "s3", sync_mode: "full", **config)
      super(
        id: id,
        source_type: "file_upload",
        name: name || SourceNames.file_upload,
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(storage_provider: storage_provider, sync_mode: sync_mode))
      )
    end
  end

  # Escape hatch for API-compatible source types/configs not yet modeled by the SDK.
  class GenericSource < Source
  end
end
