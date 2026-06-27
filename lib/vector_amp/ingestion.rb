# frozen_string_literal: true

require "pathname"
require "net/http"
require_relative "source"
require_relative "utils"

module VectorAmp
  # Ingestion API resource for sources, jobs, and direct file uploads.
  class IngestionResource
    # @param transport [#request] API transport.
    # @return [IngestionResource]
    def initialize(transport)
      @transport = transport
    end

    # List ingestion sources.
    # @param limit [Integer] page size; defaults to 50.
    # @param offset [Integer] page offset; defaults to 0.
    # @return [Hash] response envelope from the API.
    def list_sources(limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/sources", query: { limit: limit, offset: offset })
    end

    # Fetch an ingestion source.
    # @param source_id [String] source id.
    # @return [Hash] source response.
    def get_source(source_id)
      @transport.request(:get, "/ingestion/sources/#{source_id}")
    end

    # Delete an ingestion source.
    # @param source_id [String] source id.
    # @param force [Boolean] force deletion even if the source is still referenced; sends `?force=true`.
    # @return [Hash] delete response.
    def delete_source(source_id, force: false)
      query = force ? { force: true } : nil
      @transport.request(:delete, "/ingestion/sources/#{source_id}", query: query)
    end

    # List sources that are not referenced by any job, schedule, or dataset.
    # @param limit [Integer] page size; defaults to 50.
    # @param offset [Integer] page offset; defaults to 0.
    # @return [Hash] response envelope from the API.
    def list_unused_sources(limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/sources/unused", query: { limit: limit, offset: offset })
    end

    # Delete all unused (unreferenced) sources.
    # @return [Hash] cleanup response.
    def cleanup_unused_sources
      @transport.request(:post, "/ingestion/sources/cleanup")
    end

    # List references (jobs, schedules, datasets) that use a source.
    # @param source_id [String] source id.
    # @return [Hash] references response.
    def source_references(source_id)
      @transport.request(:get, "/ingestion/sources/#{source_id}/references")
    end

    # Validate a source type and config without creating a source.
    # @param source_type [String, Symbol] source type to validate.
    # @param config [Hash] source-specific config to validate.
    # @return [Hash] validation response.
    def validate_source(source_type:, config:)
      @transport.request(:post, "/ingestion/sources/validate", body: { source_type: source_type, config: config })
    end

    # Create an ingestion source from a Source object/hash or explicit options.
    # @param source [Source, Hash, nil] optional source object/hash; when supplied, option fields are ignored.
    # @param source_type [String, Symbol, nil] source type (`s3`, `web`, `gdrive`, or `file_upload`).
    # @param name [String, nil] source name; defaults by source type when omitted.
    # @param config [Hash, nil] source-specific config.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @return [Hash] created source response.
    def create_source(source = nil, source_type: nil, name: nil, config: nil, description: nil, metadata: nil)
      body = source ? source_create_body(source) : source_create_body_from_options(
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
      @transport.request(:post, "/ingestion/sources", body: body)
    end

    # Alias for {#create_source}.
    # @return [Hash] created source response.
    def create(source = nil, **options)
      create_source(source, **options)
    end

    # Create a web source.
    # @param start_urls [String, Array<String>] required seed URLs.
    # @param name [String, nil] defaults to `web-<host>` from the first URL, or `web-source`.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param config [Hash] additional web-source config forwarded to the API.
    # @return [Hash] created source response.
    def create_web(start_urls:, name: nil, description: nil, metadata: nil, **config)
      create_source(WebSource.new(
        name: name,
        start_urls: start_urls,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    # Create an S3 source.
    # @param bucket [String] required S3 bucket name.
    # @param name [String, nil] defaults to `s3-<bucket>` or `s3-<bucket>-<prefix>`.
    # @param prefix [String, nil] optional object prefix.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param config [Hash] additional S3-source config forwarded to the API.
    # @return [Hash] created source response.
    def create_s3(bucket:, name: nil, prefix: nil, description: nil, metadata: nil, **config)
      create_source(S3Source.new(
        name: name,
        bucket: bucket,
        prefix: prefix,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    # Create a Google Cloud Storage source.
    # @param bucket [String] required GCS bucket name.
    # @param name [String, nil] defaults to `gcs-<bucket>` or `gcs-<bucket>-<prefix>`.
    # @param prefix [String, nil] optional object prefix.
    # @param connection_id [String, nil] optional managed connection id used in place of inline credentials.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param config [Hash] additional GCS-source config forwarded to the API.
    # @return [Hash] created source response.
    def create_gcs(bucket:, name: nil, prefix: nil, connection_id: nil, description: nil, metadata: nil, **config)
      create_source(GCSSource.new(
        bucket: bucket,
        name: name,
        prefix: prefix,
        connection_id: connection_id,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    def create_jira(cloud_id:, name: nil, access_token: nil, project_keys: nil, jql: nil, include_comments: true, connection_id: nil, description: nil, metadata: nil, **config)
      create_source(JiraSource.new(
        cloud_id: cloud_id,
        name: name,
        access_token: access_token,
        project_keys: project_keys,
        jql: jql,
        include_comments: include_comments,
        connection_id: connection_id,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    # Create a Google Drive source.
    # @param name [String, nil] defaults to `google-drive-<first id>` or `google-drive-source`.
    # @param folder_ids [String, Array<String>, nil] folder ids to ingest; required if file_ids is empty.
    # @param file_ids [String, Array<String>, nil] file ids to ingest; required if folder_ids is empty.
    # @param auth_mode [String, nil] auth strategy (`service_account`, `oauth`); omitted when nil.
    # @param service_account_json [Hash, String, nil] service-account credentials for `service_account` auth.
    # @param oauth_credentials [Hash, nil] OAuth credentials for `oauth` auth.
    # @param connection_id [String, nil] optional managed connection id used in place of inline credentials.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param config [Hash] additional Google Drive-source config forwarded to the API.
    # @return [Hash] created source response.
    def create_google_drive(name: nil, folder_ids: nil, file_ids: nil, auth_mode: nil, service_account_json: nil,
                            oauth_credentials: nil, connection_id: nil, description: nil, metadata: nil, **config)
      create_source(GoogleDriveSource.new(
        name: name,
        folder_ids: folder_ids,
        file_ids: file_ids,
        auth_mode: auth_mode,
        service_account_json: service_account_json,
        oauth_credentials: oauth_credentials,
        connection_id: connection_id,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    # Create a Confluence source.
    # @param cloud_id [String, nil] Atlassian OAuth cloud/site id; required unless base_url is given.
    # @param base_url [String, nil] Confluence base URL, e.g. https://company.atlassian.net.
    # @param name [String, nil] defaults to `confluence-<space>`/`confluence-<host>`/`confluence-source`.
    # @param auth_mode [String] `basic` (default) or `oauth`.
    # @param username [String, nil] username for basic auth.
    # @param api_token [String, nil] API token for basic auth.
    # @param spaces [String, Array<String>, nil] space keys to ingest; empty means all accessible.
    # @param include_attachments [Boolean] include page attachments; defaults to false.
    # @param connection_id [String, nil] optional managed connection id used in place of inline credentials.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param config [Hash] additional Confluence-source config forwarded to the API.
    # @return [Hash] created source response.
    def create_confluence(cloud_id: nil, base_url: nil, name: nil, auth_mode: "basic", username: nil, api_token: nil,
                          spaces: nil, include_attachments: false, connection_id: nil, description: nil, metadata: nil, **config)
      create_source(ConfluenceSource.new(
        cloud_id: cloud_id,
        base_url: base_url,
        name: name,
        auth_mode: auth_mode,
        username: username,
        api_token: api_token,
        spaces: spaces,
        include_attachments: include_attachments,
        connection_id: connection_id,
        description: description,
        metadata: metadata,
        **config
      ))
    end

    # Create a file-upload source.
    # @param name [String, nil] defaults to timestamped `ruby-sdk-file-upload-YYYYmmddHHMMSS`.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param storage_provider [String] storage backend; defaults to `s3`.
    # @param sync_mode [String] sync strategy; defaults to `full`.
    # @param config [Hash] additional file-upload config forwarded to the API.
    # @return [Hash] created source response.
    def create_file_upload(name: nil, description: nil, metadata: nil, storage_provider: "s3", sync_mode: "full", **config)
      create_source(FileUploadSource.new(
        name: name,
        description: description,
        metadata: metadata,
        storage_provider: storage_provider,
        sync_mode: sync_mode,
        **config
      ))
    end

    # Start an ingestion job for a source and dataset.
    # @param source_id [String] source id.
    # @param dataset_id [String] target dataset id.
    # @param pipeline_id [String, nil] optional pipeline id.
    # @return [Hash] ingestion job response.
    def start_job(source_id:, dataset_id:, pipeline_id: nil)
      @transport.request(:post, "/ingestion/jobs", body: Utils.compact_hash(
        source_id: source_id,
        dataset_id: dataset_id,
        pipeline_id: pipeline_id
      ))
    end

    # List ingestion jobs.
    # @param dataset_id [String, nil] optional dataset filter.
    # @param limit [Integer] page size; defaults to 50.
    # @param offset [Integer] page offset; defaults to 0.
    # @return [Hash] response envelope from the API.
    def list_jobs(dataset_id: nil, limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/jobs", query: Utils.compact_hash(dataset_id: dataset_id, limit: limit, offset: offset))
    end

    # Fetch an ingestion job.
    # @param job_id [String] job id.
    # @return [Hash] job response.
    def get_job(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}")
    end

    # Retry an eligible failed or cancelled ingestion job as a fresh full rerun.
    # @param job_id [String] original job id.
    # @return [Hash] newly queued retry job response.
    def retry_job(job_id)
      @transport.request(:post, "/ingestion/jobs/#{job_id}/retry")
    end

    # List files attached to an ingestion job.
    # @param job_id [String] job id.
    # @return [Hash] files response.
    def job_files(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}/files")
    end

    # Fetch ingestion job statistics.
    # @param job_id [String] job id.
    # @return [Hash] statistics response.
    def job_statistics(job_id)
      @transport.request(:get, "/ingestion/jobs/#{job_id}/statistics")
    end

    # Cancel an ingestion job.
    # @param job_id [String] job id.
    # @return [Hash] cancel response.
    def cancel_job(job_id)
      @transport.request(:delete, "/ingestion/jobs/#{job_id}/cancel")
    end

    # Upload local files by auto-creating a `file_upload` source, initializing presigned uploads, and completing the upload job.
    # @param dataset_id [String] target dataset id; also added to source metadata.
    # @param paths [String, Array<String>] local file paths to upload.
    # @param source_name [String, nil] optional source name; defaults to timestamped Ruby SDK file-upload name.
    # @param description [String, nil] optional source description.
    # @param metadata [Hash] optional source metadata merged with dataset_id.
    # @return [Hash] upload completion/job response.
    def ingest_files(dataset_id:, paths:, source_name: nil, description: nil, metadata: {})
      files = Array(paths).map { |path| Pathname(path) }
      raise ArgumentError, "paths must not be empty" if files.empty?

      source = create_file_upload(
        name: source_name,
        description: description,
        metadata: (metadata || {}).merge(dataset_id: dataset_id)
      )
      source_id = source.fetch("id") { source.fetch(:id) }

      init = init_upload(source_id, files)
      upload_files_to_presigned_urls(files, init.fetch("uploads"))
      job_id = init.fetch("job_id")
      response = complete_upload(source_id, job_id: job_id, file_ids: init.fetch("uploads").map { |upload| upload.fetch("file_id") })
      response["job_id"] ||= job_id if response.is_a?(Hash)
      response
    end

    # Initialize presigned uploads for source files.
    # @param source_id [String] file-upload source id.
    # @param files [Array<String, Pathname>] local files.
    # @return [Hash] init response containing uploads and job_id.
    def init_upload(source_id, files)
      payload = Array(files).map do |file|
        path = Pathname(file)
        {
          name: path.to_s,
          size_bytes: path.size,
          content_type: content_type_for(path)
        }
      end
      @transport.request(:post, "/ingestion/sources/#{source_id}/upload/init", body: { files: payload })
    end

    # Complete a file upload job after files have been PUT to presigned URLs.
    # @param source_id [String] file-upload source id.
    # @param job_id [String] upload job id from {#init_upload}.
    # @param file_ids [Array<String>] file ids from {#init_upload}.
    # @return [Hash] upload completion/job response.
    def complete_upload(source_id, job_id:, file_ids:)
      @transport.request(:post, "/ingestion/sources/#{source_id}/upload/complete", body: { job_id: job_id, file_ids: file_ids })
    end

    private

    def source_create_body(source)
      return source.to_create_body if source.respond_to?(:to_create_body)

      hash = Source.normalize_hash(source)
      source_create_body_from_options(
        source_type: hash["source_type"],
        name: hash["name"],
        description: hash["description"],
        config: hash["config"],
        metadata: hash["metadata"]
      )
    end

    def source_create_body_from_options(source_type:, name:, config:, description: nil, metadata: nil)
      resolved_type = source_type&.to_s
      Utils.compact_hash(
        source_type: resolved_type,
        name: name || default_source_name(resolved_type, config || {}),
        description: description,
        config: config,
        metadata: metadata
      )
    end

    def default_source_name(source_type, config)
      case source_type
      when "file_upload" then SourceNames.file_upload
      when "web" then SourceNames.web(config[:start_urls] || config["start_urls"])
      when "s3" then SourceNames.s3(config[:bucket] || config["bucket"], config[:prefix] || config["prefix"])
      when "gcs" then SourceNames.gcs(config[:bucket] || config["bucket"], config[:prefix] || config["prefix"])
      when "jira" then SourceNames.jira(project_keys: config[:project_keys] || config["project_keys"], cloud_id: config[:cloud_id] || config["cloud_id"])
      when "confluence" then SourceNames.confluence(spaces: config[:spaces] || config["spaces"], cloud_id: config[:cloud_id] || config["cloud_id"], base_url: config[:base_url] || config["base_url"])
      when "gdrive" then SourceNames.google_drive(folder_ids: config[:folder_ids] || config["folder_ids"], file_ids: config[:file_ids] || config["file_ids"])
      end
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
