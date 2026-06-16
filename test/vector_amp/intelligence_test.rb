# frozen_string_literal: true

require "test_helper"

class VectorAmpIntelligenceTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_non_streaming_ask
    stub_request(:post, "#{API}/intelligence/query")
      .with(body: { query: "What?", dataset_id: "all", stream: false })
      .to_return_json(body: { answer: "42", sources: [], chunks: [], metadata: {} })

    response = @client.ask("What?", dataset_id: "all")

    assert_equal "42", response.fetch("answer")
  end

  def test_multi_turn_sends_conversation_history
    history = [
      { role: "user", content: "What is VectorAmp?" },
      { role: "assistant", content: "A vector database platform." }
    ]
    stub_request(:post, "#{API}/intelligence/query")
      .with(body: {
        query: "Does it support hybrid search?",
        dataset_id: "ds_1",
        conversation_history: history,
        stream: false
      })
      .to_return_json(body: { answer: "Yes.", sources: [], chunks: [], metadata: {} })

    response = @client.intelligence.query(
      "Does it support hybrid search?",
      dataset_id: "ds_1",
      conversation_history: history
    )

    assert_equal "Yes.", response.fetch("answer")
  end

  def test_streaming_ask_yields_sse_events
    body = <<~SSE
      data: {"chunk_type":"text","content":"hello","metadata":{}}

      data: {"chunk_type":"done","content":"","metadata":{}}

    SSE
    stub_request(:post, "#{API}/intelligence/query")
      .with(body: { query: "Say hi", stream: true })
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

    events = []
    @client.ask_stream("Say hi") { |event| events << event }

    assert_equal %w[text done], events.map { |event| event.fetch("chunk_type") }
  end

  def test_streaming_ask_can_return_enumerator
    transport = EnumeratorTransport.new
    client = VectorAmp::Client.new(api_key: "key", transport: transport)

    assert_equal [{ "chunk_type" => "done" }], client.ask_stream("hi").to_a
  end

  class EnumeratorTransport
    def request(_method, _path, stream: false, **_options)
      raise "expected stream" unless stream

      yield({ "chunk_type" => "done" })
    end
  end
end
