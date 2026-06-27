# frozen_string_literal: true

require "test_helper"

class VectorAmpConnectionsTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_list_create_get_delete
    stub_request(:get, "#{API}/connections")
      .to_return_json(body: {
        connections: [{ id: "conn_1", provider: "google_drive", status: "active" }],
        total: 1,
      })
    stub_request(:get, "#{API}/connections?provider=google_drive")
      .to_return_json(body: {
        connections: [{ id: "conn_1", provider: "google_drive", status: "active" }],
        total: 1,
      })
    stub_request(:post, "#{API}/connections")
      .with(body: { provider: "google_drive", source_type: "gdrive" })
      .to_return_json(status: 201, body: {
        id: "conn_2",
        provider: "google_drive",
        status: "pending",
        authorization_url: "https://accounts.google.com/o/oauth2/auth?x=1",
      })
    stub_request(:get, "#{API}/connections/conn_1")
      .to_return_json(body: { id: "conn_1", provider: "google_drive", status: "active" })
    stub_request(:delete, "#{API}/connections/conn_1")
      .to_return_json(body: { deleted: true })

    assert_equal "conn_1", @client.connections.list.fetch("connections").first.fetch("id")
    assert_equal "conn_1", @client.connections.list(provider: "google_drive").fetch("connections").first.fetch("id")

    created = @client.connections.create("google_drive", source_type: "gdrive")
    assert_equal "conn_2", created.fetch("id")
    assert_equal "google_drive", created.fetch("provider")
    assert_equal "pending", created.fetch("status")
    assert_match(%r{accounts\.google\.com}, created.fetch("authorization_url"))

    assert_equal "active", @client.connections.get("conn_1").fetch("status")
    assert_equal true, @client.connections.delete("conn_1").fetch("deleted")
  end

  def test_create_without_source_type
    stub_request(:post, "#{API}/connections")
      .with(body: { provider: "confluence" })
      .to_return_json(status: 201, body: {
        id: "conn_3",
        provider: "confluence",
        status: "pending",
        authorization_url: "https://auth.example.com/oauth",
      })

    created = @client.connections.create("confluence")
    assert_equal "conn_3", created.fetch("id")
    assert_equal "pending", created.fetch("status")
  end
end
