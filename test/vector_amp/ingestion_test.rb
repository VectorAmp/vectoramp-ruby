# frozen_string_literal: true

require "test_helper"
require "tempfile"

class VectorAmpIngestionTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_sources_and_jobs_use_pagination_envelopes
    stub_request(:get, "#{API}/ingestion/sources?limit=5&offset=10")
      .to_return_json(body: { sources: [], total: 0, limit: 5, offset: 10 })
    stub_request(:get, "#{API}/ingestion/jobs?dataset_id=ds_1&limit=7&offset=9")
      .to_return_json(body: { jobs: [], total: 0, limit: 7, offset: 9 })

    assert_equal 10, @client.ingestion.list_sources(limit: 5, offset: 10).fetch("offset")
    assert_equal 7, @client.ingestion.list_jobs(dataset_id: "ds_1", limit: 7, offset: 9).fetch("limit")
  end

  def test_source_and_job_helpers
    stub_request(:get, "#{API}/ingestion/sources/src_1").to_return_json(body: { id: "src_1" })
    stub_request(:post, "#{API}/v1/sources")
      .with(body: hash_including(source_type: "web", name: "site", config: { start_urls: ["https://example.com"] }))
      .to_return_json(status: 201, body: { id: "src_2" })
    stub_request(:post, "#{API}/ingestion/jobs")
      .with(body: { source_id: "src_2", dataset_id: "ds_1" })
      .to_return_json(body: { job_id: "job_1" })
    stub_request(:get, "#{API}/ingestion/jobs/job_1").to_return_json(body: { job_id: "job_1" })
    stub_request(:post, "#{API}/ingestion/jobs/job_1/retry").to_return_json(body: { job_id: "job_2", status: "pending" })
    stub_request(:get, "#{API}/ingestion/jobs/job_1/files").to_return_json(body: { files: [] })
    stub_request(:get, "#{API}/ingestion/jobs/job_1/statistics").to_return_json(body: { total_files: 0 })
    stub_request(:delete, "#{API}/ingestion/jobs/job_1/cancel").to_return_json(body: { cancelled: true })

    assert_equal "src_1", @client.ingestion.get_source("src_1").fetch("id")
    assert_equal "src_2", @client.ingestion.create_source(source_type: "web", name: "site", config: { start_urls: ["https://example.com"] }).fetch("id")
    assert_equal "job_1", @client.ingestion.start_job(source_id: "src_2", dataset_id: "ds_1").fetch("job_id")
    assert_equal "job_1", @client.ingestion.get_job("job_1").fetch("job_id")
    assert_equal "job_2", @client.ingestion.retry_job("job_1").fetch("job_id")
    assert_equal [], @client.ingestion.job_files("job_1").fetch("files")
    assert_equal 0, @client.ingestion.job_statistics("job_1").fetch("total_files")
    assert_equal true, @client.ingestion.cancel_job("job_1").fetch("cancelled")
  end

  def test_typed_source_builders_and_create_helpers
    web = VectorAmp::WebSource.new(name: "docs", start_urls: ["https://docs.example.com"], max_depth: 2)
    assert_equal "web", web.source_type
    assert_equal({ start_urls: ["https://docs.example.com"], max_depth: 2 }, web.config)
    assert_includes VectorAmp::Source::SUPPORTED_SOURCE_TYPES, "gdrive"

    generic = VectorAmp::GenericSource.new(
      source_type: "custom",
      name: "custom-source",
      config: { endpoint: "https://example.com/feed" }
    )
    assert_equal "custom", generic.source_type

    stub_request(:post, "#{API}/v1/sources")
      .with(body: { source_type: "web", name: "docs", config: { start_urls: ["https://docs.example.com"], max_depth: 2 } })
      .to_return_json(status: 201, body: { id: "src_web" })
    stub_request(:post, "#{API}/v1/sources")
      .with(body: { source_type: "s3", name: "bucket", config: { bucket: "docs-bucket", prefix: "manuals/", region: "us-east-1" } })
      .to_return_json(status: 201, body: { id: "src_s3" })
    stub_request(:post, "#{API}/v1/sources")
      .with(body: { source_type: "gdrive", name: "drive", config: { folder_ids: ["folder_1"] } })
      .to_return_json(status: 201, body: { id: "src_drive" })
    stub_request(:post, "#{API}/v1/sources")
      .with(body: { source_type: "file_upload", name: "upload", config: { storage_provider: "s3", sync_mode: "full" } })
      .to_return_json(status: 201, body: { id: "src_upload" })
    stub_request(:post, "#{API}/v1/sources")
      .with(body: { source_type: "custom", name: "custom-source", config: { endpoint: "https://example.com/feed" } })
      .to_return_json(status: 201, body: { id: "src_custom" })

    assert_equal "src_web", @client.sources.create(web).fetch("id")
    assert_equal "src_s3", @client.sources.create_s3(name: "bucket", bucket: "docs-bucket", prefix: "manuals/", region: "us-east-1").fetch("id")
    assert_equal "src_drive", @client.sources.create_google_drive(name: "drive", folder_ids: ["folder_1"]).fetch("id")
    assert_equal "src_upload", @client.sources.create_file_upload(name: "upload").fetch("id")
    assert_equal "src_custom", @client.sources.create_source(generic).fetch("id")
  end

  def test_source_objects_expose_hash_helpers_and_new_source_defaults
    source = VectorAmp::Source.from_api(
      "id" => "src_1",
      "source_type" => "gcs",
      "name" => "gcs-docs",
      "description" => "docs bucket",
      "config" => { "bucket" => "docs" },
      "metadata" => { "team" => "docs" }
    )

    assert_equal "src_1", source[:id]
    assert_equal "gcs", source["source_type"]
    assert_equal "docs bucket", source.to_h.fetch(:description)
    assert_equal({ source_type: "gcs", name: "gcs-docs", description: "docs bucket", config: { "bucket" => "docs" }, metadata: { "team" => "docs" } }, source.to_create_body)
    assert_match(/GenericSource/, source.inspect)

    gcs = VectorAmp::GCSSource.new(bucket: "docs", prefix: "manuals/", project_id: "proj")
    assert_equal "gcs", gcs.source_type
    assert_equal "gcs-docs-manuals", gcs.name
    assert_equal({ bucket: "docs", prefix: "manuals/", project_id: "proj" }, gcs.config)

    jira = VectorAmp::JiraSource.new(cloud_id: "cloud", project_keys: ["ENG"], jql: "project = ENG", access_token: "tok", sync_mode: "full")
    assert_equal "jira", jira.source_type
    assert_equal "jira-ENG", jira.name
    assert_equal true, jira.config.fetch(:include_comments)
    assert_equal "full", jira.config.fetch(:sync_mode)
    assert_raises(ArgumentError) { VectorAmp::GCSSource.new(bucket: "") }
    assert_raises(ArgumentError) { VectorAmp::JiraSource.new(cloud_id: nil) }
    assert_raises(ArgumentError) { VectorAmp::Source.new(source_type: nil, name: "x", config: {}) }
    assert_raises(ArgumentError) { VectorAmp::Source.new(source_type: "web", name: "x", config: nil) }
  end

  def test_typed_source_builders_default_names
    assert_equal "web-docs.example.com", VectorAmp::WebSource.new(start_urls: ["https://docs.example.com"]).name
    assert_equal "s3-docs-bucket-manuals", VectorAmp::S3Source.new(bucket: "docs-bucket", prefix: "manuals/").name
    assert_equal "google-drive-folder_1", VectorAmp::GoogleDriveSource.new(folder_ids: ["folder_1"]).name
    assert_match(/\Aruby-sdk-file-upload-\d{14}\z/, VectorAmp::FileUploadSource.new.name)
  end

  def test_create_source_defaults_known_source_names
    stub_request(:post, "#{API}/v1/sources")
      .with(body: hash_including(source_type: "web", name: "web-docs.example.com", config: { start_urls: ["https://docs.example.com"] }))
      .to_return_json(status: 201, body: { id: "src_web" })

    assert_equal "src_web", @client.sources.create_source(source_type: "web", config: { start_urls: ["https://docs.example.com"] }).fetch("id")
  end

  def test_typed_sources_validate_required_fields
    assert_raises(ArgumentError) { VectorAmp::WebSource.new(name: "docs", start_urls: []) }
    assert_raises(ArgumentError) { VectorAmp::S3Source.new(name: "bucket", bucket: "") }
    assert_raises(ArgumentError) { VectorAmp::GoogleDriveSource.new(name: "drive") }
  end

  def test_ingest_files_uploads_to_presigned_url_and_completes
    file = Tempfile.new(["vectoramp", ".txt"])
    file.write("hello")
    file.close

    stub_request(:post, "#{API}/v1/sources")
      .with { |request|
        body = JSON.parse(request.body)
        body["source_type"] == "file_upload" &&
          body["name"].match?(/\Aruby-sdk-file-upload-\d{14}\z/) &&
          body["metadata"] == { "dataset_id" => "ds_1", "project" => "docs" }
      }
      .to_return_json(status: 201, body: { id: "src_1" })
    stub_request(:post, "#{API}/v1/sources/src_1/upload/init")
      .with { |request| JSON.parse(request.body).fetch("files").first.fetch("content_type") == "text/plain" }
      .to_return_json(body: { job_id: "job_1", uploads: [{ file_id: "file_1", file_name: File.basename(file.path), upload_url: "https://uploads.test/file_1" }] })
    upload = stub_request(:put, "https://uploads.test/file_1").with(body: "hello").to_return(status: 200, body: "")
    stub_request(:post, "#{API}/v1/sources/src_1/upload/complete")
      .with(body: { job_id: "job_1", file_ids: ["file_1"] })
      .to_return_json(body: { job_id: "job_1", status: "pending" })

    response = @client.ingestion.ingest_files(dataset_id: "ds_1", paths: [file.path], metadata: { project: "docs" })

    assert_requested upload
    assert_equal "pending", response.fetch("status")
  ensure
    file.unlink if file
  end
end
