# frozen_string_literal: true

require "test_helper"

class VectorAmpDatasetsTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_list_returns_pagination_envelope_with_dataset_resources
    stub_request(:get, "#{API}/datasets?limit=10&offset=20")
      .with(headers: { "X-API-Key" => "test-key" })
      .to_return_json(body: { datasets: [{ id: "ds_1", name: "docs" }], total: 1, limit: 10, offset: 20 })

    response = @client.datasets.list(limit: 10, offset: 20)
    dataset = response.fetch("datasets").first

    assert_equal 1, response.fetch("total")
    assert_instance_of VectorAmp::Dataset, dataset
    assert_equal "ds_1", dataset.id
    assert_equal "docs", dataset.fetch("name")
  end

  def test_get_and_delete_dataset
    stub_request(:get, "#{API}/datasets/ds_1").to_return_json(body: { id: "ds_1" })
    stub_request(:delete, "#{API}/datasets/ds_1").to_return_json(body: { deleted: true })

    dataset = @client.datasets.get("ds_1")

    assert_instance_of VectorAmp::Dataset, dataset
    assert_equal "ds_1", dataset.fetch("id")
    assert_equal true, @client.datasets.delete("ds_1").fetch("deleted")
    assert_equal true, dataset.delete.fetch("deleted")
  end

  def test_create_forces_sable_and_rejects_index_type
    stub = stub_request(:post, "#{API}/datasets")
           .with(body: hash_including(index_type: "sable", name: "docs", dim: 3, metric: "cosine"))
           .to_return_json(status: 201, body: { id: "ds_1", index_type: "sable" })

    response = @client.datasets.create(name: "docs", dim: 3, embedding: { provider: "vectoramp", model: "Qwen" })

    assert_requested stub
    assert_instance_of VectorAmp::Dataset, response
    assert_equal "ds_1", response.id
    assert_equal "sable", response.fetch("index_type")
    assert_raises(ArgumentError) do
      @client.datasets.create(name: "docs", dim: 3, embedding: {}, index_type: "hnsw")
    end
  end

  def test_search_sends_supported_options
    stub = stub_request(:post, "#{API}/datasets/ds_1/search")
           .with(body: hash_including(query_text: "hello", top_k: 5, include_metadata: false, filters: { category: "docs" }))
           .to_return_json(body: { results: [], dataset_id: "ds_1" })

    response = @client.datasets.search("ds_1", query_text: "hello", top_k: 5, filters: { category: "docs" }, include_metadata: false)

    assert_requested stub
    assert_equal [], response.fetch("results")
  end

  def test_insert_vectors
    vectors = [{ id: "a", values: [0.1], metadata: { title: "A" } }]
    stub_request(:post, "#{API}/datasets/ds_1/insert")
      .with(body: { vectors: vectors })
      .to_return_json(body: { inserted: 1 })

    assert_equal 1, @client.datasets.insert("ds_1", vectors: vectors).fetch("inserted")
  end

  def test_add_texts_embeds_and_inserts
    stub_request(:post, "#{API}/datasets/ds_1/embed")
      .with(body: { texts: %w[alpha beta] })
      .to_return_json(body: { embeddings: [[0.1], [0.2]] })
    insert = stub_request(:post, "#{API}/datasets/ds_1/insert")
             .with { |request|
               body = JSON.parse(request.body)
               body["vectors"].length == 2 &&
                 body["vectors"].first["id"] == "a" &&
                 body["vectors"].first["metadata"] == { "kind" => "note", "text" => "alpha" }
             }
             .to_return_json(body: { inserted: 2 })

    response = @client.datasets.add_texts("ds_1", texts: %w[alpha beta], ids: %w[a b], metadata: { kind: "note" })

    assert_requested insert
    assert_equal 2, response.fetch("inserted")
  end

  def test_dataset_instance_methods_delegate_to_services
    dataset = VectorAmp::Dataset.new({ id: "ds_1", name: "docs" }, service: @client.datasets, client: @client)
    vectors = [{ id: "a", values: [0.1], metadata: { title: "A" } }]

    stub_request(:post, "#{API}/datasets/ds_1/search")
      .with(body: hash_including(query_text: "hello"))
      .to_return_json(body: { results: ["hit"] })
    stub_request(:post, "#{API}/datasets/ds_1/insert")
      .with(body: { vectors: vectors })
      .to_return_json(body: { inserted: 1 })
    stub_request(:post, "#{API}/intelligence/query")
      .with(body: hash_including(query: "question", dataset_id: "ds_1"))
      .to_return_json(body: { answer: "42" })
    stub_request(:get, "#{API}/datasets/ds_1/stats").to_return_json(body: { vector_count: 1 })

    assert_equal ["hit"], dataset.search(query_text: "hello").fetch("results")
    assert_equal 1, dataset.insert(vectors: vectors).fetch("inserted")
    assert_equal "42", dataset.ask("question").fetch("answer")
    assert_equal 1, dataset.stats.fetch("vector_count")
    assert_equal({ "id" => "ds_1", "name" => "docs" }, dataset.to_h)
    assert_equal({ "id" => "ds_1", "name" => "docs" }, dataset.raw_data)
  end

  def test_dataset_instance_add_texts_and_ingestion_helpers
    dataset = VectorAmp::Dataset.new({ id: "ds_1" }, service: @client.datasets, client: @client)

    stub_request(:post, "#{API}/datasets/ds_1/embed")
      .with(body: { texts: ["alpha"] })
      .to_return_json(body: { embeddings: [[0.1]] })
    stub_request(:post, "#{API}/datasets/ds_1/insert")
      .to_return_json(body: { inserted: 1 })
    stub_request(:post, "#{API}/ingestion/jobs")
      .with(body: { source_id: "src_1", dataset_id: "ds_1" })
      .to_return_json(body: { job_id: "job_1" })

    assert_equal 1, dataset.add_texts(texts: ["alpha"], ids: ["a"]).fetch("inserted")
    assert_equal "job_1", dataset.ingest_source("src_1").fetch("job_id")
  end

  def test_dataset_ingest_source_accepts_typed_source_object
    dataset = VectorAmp::Dataset.new({ id: "ds_1" }, service: @client.datasets, client: @client)
    source = VectorAmp::WebSource.new(id: "src_1", name: "docs", start_urls: ["https://docs.example.com"])

    stub_request(:post, "#{API}/ingestion/jobs")
      .with(body: { source_id: "src_1", dataset_id: "ds_1", pipeline_id: "pipe_1" })
      .to_return_json(body: { job_id: "job_1" })

    assert_equal "job_1", dataset.ingest_source(source, pipeline_id: "pipe_1").fetch("job_id")
  end

  def test_add_texts_validates_lengths
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: [], ids: []) }
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: ["a"], ids: []) }
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: ["a"], metadata: [{}, {}]) }
  end
end
