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

  def test_sessions_lifecycle
    stub_request(:post, "#{API}/intelligence/sessions")
      .with(body: { title: "Onboarding", dataset_id: "ds_1" })
      .to_return_json(status: 201, body: { id: "sess_1", title: "Onboarding" })
    stub_request(:get, "#{API}/intelligence/sessions?limit=20")
      .to_return_json(body: { sessions: [{ id: "sess_1" }] })
    stub_request(:get, "#{API}/intelligence/sessions/sess_1")
      .to_return_json(body: { id: "sess_1", title: "Onboarding" })
    stub_request(:post, "#{API}/intelligence/sessions/sess_1/messages")
      .with(body: { role: "user", content: "What is SABLE?" })
      .to_return_json(status: 201, body: { id: "msg_1", role: "user", content: "What is SABLE?" })
    stub_request(:get, "#{API}/intelligence/sessions/sess_1/messages?limit=100")
      .to_return_json(body: { messages: [{ id: "msg_1" }] })
    stub_request(:delete, "#{API}/intelligence/sessions/sess_1")
      .to_return_json(body: { deleted: true })

    session = @client.intelligence.create_session(title: "Onboarding", dataset_id: "ds_1")
    assert_equal "sess_1", session.fetch("id")

    assert_equal "sess_1", @client.intelligence.list_sessions(limit: 20).fetch("sessions").first.fetch("id")
    assert_equal "Onboarding", @client.intelligence.get_session("sess_1").fetch("title")

    message = @client.intelligence.append_message("sess_1", role: "user", content: "What is SABLE?")
    assert_equal "msg_1", message.fetch("id")

    assert_equal "msg_1", @client.intelligence.list_messages("sess_1").fetch("messages").first.fetch("id")
    assert_equal true, @client.intelligence.delete_session("sess_1").fetch("deleted")
  end

  class EnumeratorTransport
    def request(_method, _path, stream: false, **_options)
      raise "expected stream" unless stream

      yield({ "chunk_type" => "done" })
    end
  end
end
