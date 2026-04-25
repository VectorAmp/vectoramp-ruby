# frozen_string_literal: true

require "test_helper"

class VectorAmpTransportTest < Minitest::Test
  def test_raises_api_error_with_status_and_body
    client = VectorAmp::Client.new(api_key: "key", base_url: "https://api.test")
    stub_request(:get, "https://api.test/datasets/ds_404")
      .to_return_json(status: 404, body: { error: "not found" })

    error = assert_raises(VectorAmp::APIError) { client.datasets.get("ds_404") }

    assert_equal 404, error.status
    assert_equal({ "error" => "not found" }, error.body)
  end
end
