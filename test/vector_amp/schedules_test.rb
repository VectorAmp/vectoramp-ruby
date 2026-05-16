# frozen_string_literal: true

require "test_helper"

class VectorAmpSchedulesTest < Minitest::Test
  API = "https://api.test"

  def setup
    @client = VectorAmp::Client.new(api_key: "test-key", base_url: API)
  end

  def test_crud_and_trigger
    stub_request(:get, "#{API}/ingestion/schedules?limit=10&offset=0")
      .to_return_json(body: {
        schedules: [{ id: "sch_1", cron: "0 * * * *", enabled: true }],
        total: 1,
        limit: 10,
        offset: 0,
      })
    stub_request(:get, "#{API}/ingestion/schedules/sch_1")
      .to_return_json(body: { id: "sch_1", cron: "0 * * * *", enabled: true })
    stub_request(:post, "#{API}/ingestion/schedules")
      .with(body: { source_id: "src_1", dataset_id: "ds_1", cron: "0 0 * * *", timezone: "UTC" })
      .to_return_json(status: 201, body: { id: "sch_2", cron: "0 0 * * *", enabled: true })
    stub_request(:patch, "#{API}/ingestion/schedules/sch_2")
      .with(body: { enabled: false })
      .to_return_json(body: { id: "sch_2", enabled: false })
    stub_request(:delete, "#{API}/ingestion/schedules/sch_2")
      .to_return_json(body: { deleted: true })
    stub_request(:post, "#{API}/ingestion/schedules/sch_1/trigger")
      .to_return_json(status: 202, body: { job_id: "job_42" })

    page = @client.schedules.list(limit: 10, offset: 0)
    assert_equal 1, page.fetch("total")
    assert_equal "sch_1", page.fetch("schedules").first.fetch("id")

    assert_equal "sch_1", @client.schedules.get("sch_1").fetch("id")

    created = @client.schedules.create(
      source_id: "src_1",
      dataset_id: "ds_1",
      cron: "0 0 * * *",
      timezone: "UTC",
    )
    assert_equal "sch_2", created.fetch("id")

    updated = @client.schedules.update("sch_2", enabled: false)
    assert_equal false, updated.fetch("enabled")

    assert_equal true, @client.schedules.delete("sch_2").fetch("deleted")
    assert_equal "job_42", @client.schedules.trigger("sch_1").fetch("job_id")
  end
end
