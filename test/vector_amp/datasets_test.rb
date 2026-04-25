# frozen_string_literal: true

require "test_helper"

class VectorAmpDatasetsTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_list_returns_pagination_envelope
    stub_request(:get, "#{API}/datasets?limit=10&offset=20")
      .with(headers: { "X-API-Key" => "test-key" })
      .to_return_json(body: { datasets: [], total: 0, limit: 10, offset: 20 })

    response = @client.datasets.list(limit: 10, offset: 20)

    assert_equal({ "datasets" => [], "total" => 0, "limit" => 10, "offset" => 20 }, response)
  end

  def test_get_and_delete_dataset
    stub_request(:get, "#{API}/datasets/ds_1").to_return_json(body: { id: "ds_1" })
    stub_request(:delete, "#{API}/datasets/ds_1").to_return_json(body: { deleted: true })

    assert_equal "ds_1", @client.datasets.get("ds_1").fetch("id")
    assert_equal true, @client.datasets.delete("ds_1").fetch("deleted")
  end

  def test_create_forces_sable_and_rejects_index_type
    stub = stub_request(:post, "#{API}/datasets")
           .with(body: hash_including(index_type: "sable", name: "docs", dim: 3, metric: "cosine"))
           .to_return_json(status: 201, body: { id: "ds_1", index_type: "sable" })

    response = @client.datasets.create(name: "docs", dim: 3, embedding: { provider: "vectoramp", model: "Qwen" })

    assert_requested stub
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

  def test_add_texts_validates_lengths
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: [], ids: []) }
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: ["a"], ids: []) }
    assert_raises(ArgumentError) { @client.datasets.add_texts("ds", texts: ["a"], metadata: [{}, {}]) }
  end
end
