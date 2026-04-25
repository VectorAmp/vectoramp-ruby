# frozen_string_literal: true

require "pathname"
require "net/http"
require_relative "source"
require_relative "utils"

module VectorAmp
  class IngestionResource
    def initialize(transport)
      @transport = transport
    end

    def list_sources(limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/sources", query: { limit: limit, offset: offset })
    end

    def get_source(source_id)
      @transport.request(:get, "/ingestion/sources/#{source_id}")
    end

    def create_source(source = nil, source_type: nil, name: nil, config: nil, description: nil, metadata: nil)
      body = source ? source_create_body(source) : Utils.compact_hash(
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
      @transport.request(:post, "/v1/sources", body: body)
    end

    def create(source = nil, **options)
      create_source(source, **options)
    end

    def create_web(name:, start_urls:, description: nil, metadata: nil, **config)
      create_source(WebSource.new(
        name: name,
        start_urls: start_urls,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    def create_s3(name:, bucket:, prefix: nil, description: nil, metadata: nil, **config)
      create_source(S3Source.new(
        name: name,
        bucket: bucket,
        prefix: prefix,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    def create_google_drive(name:, folder_ids: nil, file_ids: nil, description: nil, metadata: nil, **config)
      create_source(GoogleDriveSource.new(
        name: name,
        folder_ids: folder_ids,
        file_ids: file_ids,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    def create_file_upload(name:, description: nil, metadata: nil, storage_provider: "s3", sync_mode: "full", **config)
      create_source(FileUploadSource.new(
        name: name,
        description: description,
        metadata: metadata,
        storage_provider: storage_provider,
        sync_mode: sync_mode,
        **config
      ))
    end

    def start_job(source_id:, dataset_id:, pipeline_id: nil)
      @transport.request(:post, "/ingestion/jobs", body: Utils.compact_hash(
        source_id: source_id,
        dataset_id: dataset_id,
        pipeline_id: pipeline_id
      ))
    end

    def list_jobs(dataset_id: nil, limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/jobs", query: Utils.compact_hash(dataset_id: dataset_id, limit: limit, offset: offset))
    end

    def get_job(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}")
    end

    def job_files(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}/files")
    end

    def job_statistics(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}/statistics")
    end

    def cancel_job(job_id)
      @transport.request(:delete, "/ingestion/jobs/#{job_id}/cancel")
    end

    def ingest_files(dataset_id:, paths:, source_name: nil, description: nil, metadata: {})
      files = Array(paths).map { |path| Pathname(path) }
      raise ArgumentError, "paths must not be empty" if files.empty?

      source = create_source(
        source_type: "file_upload",
        name: source_name || "ruby-sdk-upload-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}",
        description: description,
        config: { storage_provider: "s3", sync_mode: "full" },
        metadata: metadata.merge(dataset_id: dataset_id)
      )
      source_id = source.fetch("id") { source.fetch(:id) }

      init = init_upload(source_id, files)
      upload_files_to_presigned_urls(files, init.fetch("uploads"))
      complete_upload(source_id, job_id: init.fetch("job_id"), file_ids: init.fetch("uploads").map { |upload| upload.fetch("file_id") })
    end

    def init_upload(source_id, files)
      payload = Array(files).map do |file|
        path = Pathname(file)
        {
          name: path.to_s,
          size_bytes: path.size,
          content_type: content_type_for(path)
        }
      end
      @transport.request(:post, "/v1/sources/#{source_id}/upload/init", body: { files: payload })
    end

    def complete_upload(source_id, job_id:, file_ids:)
      @transport.request(:post, "/v1/sources/#{source_id}/upload/complete", body: { job_id: job_id, file_ids: file_ids })
    end

    private

    def source_create_body(source)
      return source.to_create_body if source.respond_to?(:to_create_body)

      hash = Source.normalize_hash(source)
      Utils.compact_hash(
        source_type: hash["source_type"],
        name: hash["name"],
        description: hash["description"],
        config: hash["config"],
        metadata: hash["metadata"]
      )
    end

    def upload_files_to_presigned_urls(files, uploads)
      files.zip(uploads).each do |file, upload|
        uri = URI(upload.fetch("upload_url"))
        request = Net::HTTP::Put.new(uri)
        request["Content-Type"] = content_type_for(file)
        request.body = Pathname(file).binread
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
        next if response.is_a?(Net::HTTPSuccess)

        raise APIError.new("failed to upload #{file}", status: response.code.to_i, body: response.body, headers: response.to_hash)
      end
    end

    def content_type_for(path)
      case Pathname(path).extname.downcase
      when ".txt", ".md", ".markdown" then "text/plain"
      when ".json" then "application/json"
      when ".csv" then "text/csv"
      when ".pdf" then "application/pdf"
      when ".html", ".htm" then "text/html"
      else "application/octet-stream"
      end
    end
  end
end
