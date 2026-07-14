# frozen_string_literal: true

require "test_helper"

class VectorAmpClientTest < Minitest::Test
  def test_requires_api_key
    error = assert_raises(VectorAmp::ConfigurationError) { VectorAmp::Client.new(api_key: nil) }
    assert_match(/api_key/, error.message)
  end

  def test_uses_default_base_url_and_env_api_key
    ENV["VECTORAMP_API_KEY"] = "env-key"
    client = VectorAmp::Client.new
    assert_equal "https://api.vectoramp.com", client.base_url
  ensure
    ENV.delete("VECTORAMP_API_KEY")
  end

  def test_allows_custom_transport_for_future_protocols
    transport = FakeTransport.new
    client = VectorAmp::Client.new(api_key: "key", transport: transport)
    client.datasets.list(limit: 1, offset: 2)

    assert_equal :get, transport.calls.first[:method]
    assert_equal "/datasets", transport.calls.first[:path]
  end

  def test_exposes_org_secret_helpers
    transport = FakeTransport.new
    client = VectorAmp::Client.new(api_key: "key", transport: transport)

    client.org_secrets.put_openai_api_key(api_key: "sk-test")

    call = transport.calls.first
    assert_equal :put, call[:method]
    assert_equal "/org-secrets/emb%3Aopenai%3Aapi_key", call[:path]
    assert_equal({ value: "sk-test" }, call[:body])
  end

  class FakeTransport
    attr_reader :calls

    def initialize
      @calls = []
    end

    def request(method, path, **options)
      @calls << options.merge(method: method, path: path)
      { "ok" => true }
    end
  end
end
