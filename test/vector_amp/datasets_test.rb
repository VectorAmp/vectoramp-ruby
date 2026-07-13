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

  def test_create_with_name_only_uses_managed_defaults
    stub = stub_request(:post, "#{API}/datasets")
           .with { |request|
             body = JSON.parse(request.body)
             body["name"] == "docs" &&
               body["dim"] == 2560 &&
               body["metric"] == "cosine" &&
               body["index_type"] == "sable" &&
               body["embedding"] == { "provider" => "vectoramp", "model" => "VectorAmp-Embedding-4B" } &&
               !body.key?("hybrid")
           }
           .to_return_json(status: 201, body: { id: "ds_1", index_type: "sable" })

    response = @client.datasets.create(name: "docs")

    assert_requested stub
    assert_equal "ds_1", response.id
  end

  def test_create_hybrid_sends_hybrid_true
    stub = stub_request(:post, "#{API}/datasets")
           .with(body: hash_including(name: "docs", hybrid: true, index_type: "sable", dim: 2560))
           .to_return_json(status: 201, body: { id: "ds_1" })

    @client.datasets.create(name: "docs", hybrid: true)

    assert_requested stub
  end

  def test_create_with_openai_embedding_infers_dim
    stub = stub_request(:post, "#{API}/datasets")
           .with(body: hash_including(
             name: "docs",
             dim: 3072,
             embedding: { provider: "openai", model: "text-embedding-3-large", secret_ref: "emb:openai:api_key" }
           ))
           .to_return_json(status: 201, body: { id: "ds_1" })

    @client.datasets.create(name: "docs", embedding: VectorAmp::Embedding.openai("large"))

    assert_requested stub
  end

  def test_create_requires_dim_for_unknown_model
    error = assert_raises(ArgumentError) do
      @client.datasets.create(name: "docs", embedding: { provider: "acme", model: "acme-embed" })
    end
    assert_match(/dim is required/, error.message)
  end

  def test_insert_preserves_numeric_ids_as_numbers
    stub = stub_request(:post, "#{API}/datasets/ds_1/insert")
           .with { |request|
             vectors = JSON.parse(request.body).fetch("vectors")
             # Numeric ids must serialize as JSON numbers, not strings.
             request.body.include?('"id":1') &&
               request.body.include?('"id":2.5') &&
               vectors[0]["id"] == 1 &&
               vectors[1]["id"] == "doc-3" &&
               vectors[2]["id"] == 2.5
           }
           .to_return_json(body: { inserted: 3 })

    @client.datasets.insert("ds_1", vectors: [
      { id: 1, values: [0.1] },
      { id: "doc-3", values: [0.2] },
      { id: 2.5, values: [0.3] }
    ])

    assert_requested stub
  end

  def test_add_texts_preserves_numeric_ids
    stub_request(:post, "#{API}/datasets/ds_1/embed")
      .with(body: { texts: %w[alpha beta] })
      .to_return_json(body: { embeddings: [[0.1], [0.2]] })
    insert = stub_request(:post, "#{API}/datasets/ds_1/insert")
             .with { |request|
               vectors = JSON.parse(request.body).fetch("vectors")
               request.body.include?('"id":10') &&
                 vectors[0]["id"] == 10 &&
                 vectors[1]["id"] == 11
             }
             .to_return_json(body: { inserted: 2 })

    @client.datasets.add_texts("ds_1", %w[alpha beta], ids: [10, 11])

    assert_requested insert
  end

  def test_add_texts_accepts_single_string
    stub_request(:post, "#{API}/datasets/ds_1/embed")
      .with(body: { texts: ["solo"] })
      .to_return_json(body: { embeddings: [[0.1]] })
    insert = stub_request(:post, "#{API}/datasets/ds_1/insert")
             .with { |request| JSON.parse(request.body).fetch("vectors").length == 1 }
             .to_return_json(body: { inserted: 1 })

    @client.datasets.add_texts("ds_1", "solo")

    assert_requested insert
  end


  def test_list_and_download_dataset_documents
    raw = "\x00\x01\xFFVA".b
    stub_request(:get, "#{API}/datasets/ds_1/documents?cursor=cur1&limit=2&status=ready")
      .to_return_json(body: { documents: [{ id: "doc_1", file_name: "a.pdf", download_available: true }], next_cursor: "cur2", limit: 2 })
    stub_request(:get, "#{API}/datasets/ds_1/documents/doc_1/download")
      .to_return(status: 302, headers: { "Location" => "#{API}/raw/doc_1" })
    stub_request(:get, "#{API}/raw/doc_1").to_return(body: raw, headers: { "Content-Type" => "application/octet-stream" })

    page = @client.datasets.list_documents("ds_1", limit: 2, cursor: "cur1", status: "ready")
    bytes = @client.datasets.download_document("ds_1", "doc_1")

    assert_equal "doc_1", page.fetch("documents").first.fetch("id")
    assert_equal "cur2", page.fetch("next_cursor")
    assert_equal raw, bytes.b
  end

  def test_search_sends_supported_options
    stub = stub_request(:post, "#{API}/datasets/ds_1/search")
           .with(body: hash_including(query_text: "hello", top_k: 5, include_metadata: false, filters: { category: "docs" }, rerank: true))
           .to_return_json(body: { results: [], dataset_id: "ds_1" })

    response = @client.datasets.search("ds_1", query_text: "hello", top_k: 5, filters: { category: "docs" }, include_metadata: false, rerank: true)

    assert_requested stub
    assert_equal [], response.fetch("results")
  end

  def test_search_accepts_plain_query_text
    stub = stub_request(:post, "#{API}/datasets/ds_1/search")
           .with(body: hash_including(query_text: "hello", top_k: 10))
           .to_return_json(body: { results: [], dataset_id: "ds_1" })

    response = @client.datasets.search("ds_1", "hello")

    assert_requested stub
    assert_equal [], response.fetch("results")
  end

  def test_search_text_alias_sends_only_query_text
    stub = stub_request(:post, "#{API}/datasets/ds_1/search")
           .with { |request|
             body = JSON.parse(request.body)
             body["query_text"] == "rare zebra quokka" &&
               body["top_k"] == 3 &&
               !body.key?("sparse_query") &&
               !body.key?("hybrid")
           }
           .to_return_json(body: { results: [], dataset_id: "ds_1" })

    @client.datasets.search("ds_1", search_text: "rare zebra quokka", top_k: 3)

    assert_requested stub
  end

  def test_insert_vectors
    vectors = [{ id: "a", values: [0.1], metadata: { title: "A" } }]
    stub_request(:post, "#{API}/datasets/ds_1/insert")
      .with(body: { vectors: vectors })
      .to_return_json(body: { inserted: 1 })

    assert_equal 1, @client.datasets.insert("ds_1", vectors: vectors).fetch("inserted")
  end

  def test_delete_vectors_sends_delete_body
    stub = stub_request(:delete, "#{API}/datasets/ds_1/vectors")
           .with(body: { ids: [1, "two"], write_concern: "all" })
           .to_return_json(body: { deleted: 2, dataset_id: "ds_1" })

    response = @client.datasets.delete_vectors("ds_1", ids: [1, "two"], write_concern: "all")

    assert_requested stub
    assert_equal 2, response.fetch("deleted")
  end

  def test_put_openai_key_and_create_openai_dataset_helper
    key_stub = stub_request(:put, "#{API}/org-secrets/emb%3Aopenai%3Aapi_key")
               .with(body: { api_key: "sk-test", secret_ref: "custom", validate: true, model: "text-embedding-3-small" })
               .to_return(status: 204, body: "")
    create_stub = stub_request(:post, "#{API}/datasets")
                  .with { |request|
                    body = JSON.parse(request.body)
                    body["name"] == "openai-docs" &&
                      body["dim"] == 1536 &&
                      body["embedding"] == {
                        "provider" => "openai",
                        "model" => "text-embedding-3-small",
                        "secret_ref" => "custom"
                      }
                  }
                  .to_return_json(status: 201, body: { id: "ds_openai" })

    dataset = @client.datasets.create_with_openai_api_key(name: "openai-docs", api_key: "sk-test", secret_ref: "custom", validate: true)

    assert_requested key_stub
    assert_requested create_stub
    assert_equal "ds_openai", dataset.id
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
      .with(body: hash_including(query_text: "hello", rerank: { enabled: true }))
      .to_return_json(body: { results: ["hit"] })
    stub_request(:post, "#{API}/datasets/ds_1/insert")
      .with(body: { vectors: vectors })
      .to_return_json(body: { inserted: 1 })
    stub_request(:delete, "#{API}/datasets/ds_1/vectors")
      .with(body: { ids: ["a"] })
      .to_return_json(body: { deleted: 1, dataset_id: "ds_1" })
    stub_request(:post, "#{API}/intelligence/query")
      .with(body: hash_including(query: "question", dataset_id: "ds_1"))
      .to_return_json(body: { answer: "42" })
    stub_request(:get, "#{API}/datasets/ds_1/stats").to_return_json(body: { vector_count: 1 })

    assert_equal ["hit"], dataset.search("hello", rerank: { enabled: true }).fetch("results")
    assert_equal 1, dataset.insert(vectors: vectors).fetch("inserted")
    assert_equal 1, dataset.delete_vectors(ids: ["a"]).fetch("deleted")
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

    assert_equal 1, dataset.add_texts(["alpha"], ids: ["a"]).fetch("inserted")
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
