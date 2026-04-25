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
    stub_request(:get, "#{API}/ingestion/jobs/job_1/files").to_return_json(body: { files: [] })
    stub_request(:get, "#{API}/ingestion/jobs/job_1/statistics").to_return_json(body: { total_files: 0 })
    stub_request(:delete, "#{API}/ingestion/jobs/job_1/cancel").to_return_json(body: { cancelled: true })

    assert_equal "src_1", @client.ingestion.get_source("src_1").fetch("id")
    assert_equal "src_2", @client.ingestion.create_source(source_type: "web", name: "site", config: { start_urls: ["https://example.com"] }).fetch("id")
    assert_equal "job_1", @client.ingestion.start_job(source_id: "src_2", dataset_id: "ds_1").fetch("job_id")
    assert_equal "job_1", @client.ingestion.get_job("job_1").fetch("job_id")
    assert_equal [], @client.ingestion.job_files("job_1").fetch("files")
    assert_equal 0, @client.ingestion.job_statistics("job_1").fetch("total_files")
    assert_equal true, @client.ingestion.cancel_job("job_1").fetch("cancelled")
  end

  def test_ingest_files_uploads_to_presigned_url_and_completes
    file = Tempfile.new(["vectoramp", ".txt"])
    file.write("hello")
    file.close

    stub_request(:post, "#{API}/v1/sources")
      .with(body: hash_including(source_type: "file_upload", metadata: { dataset_id: "ds_1", project: "docs" }))
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
