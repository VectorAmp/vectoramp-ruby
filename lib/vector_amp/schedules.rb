# frozen_string_literal: true

module VectorAmp
  # Recurring ingestion schedules. A schedule pairs a source with a target
  # dataset and a cron expression; the ingestion scheduler daemon polls for due
  # schedules and creates jobs as they fire.
  class SchedulesResource
    # @param transport [#request] API transport.
    # @return [SchedulesResource]
    def initialize(transport)
      @transport = transport
    end

    # List schedules.
    # @param limit [Integer] page size; defaults to 50.
    # @param offset [Integer] page offset; defaults to 0.
    # @return [Hash] `{ "schedules" => [...], "total" => Integer, "limit" => Integer, "offset" => Integer }`.
    def list(limit: 50, offset: 0)
      @transport.request(:get, "/ingestion/schedules", query: { limit: limit, offset: offset })
    end

    # Fetch one schedule.
    # @param schedule_id [String]
    # @return [Hash] schedule resource.
    def get(schedule_id)
      @transport.request(:get, "/ingestion/schedules/#{schedule_id}")
    end

    # Create a recurring schedule.
    # @param source_id [String] required.
    # @param dataset_id [String] required.
    # @param cron [String] required 5-field cron expression.
    # @param timezone [String, nil] optional IANA timezone (defaults to UTC server-side).
    # @param pipeline_id [String, nil] optional pipeline id.
    # @param enabled [Boolean, nil] optional flag (defaults to true server-side).
    # @param name [String, nil] optional human-readable name.
    # @param metadata [Hash, nil] optional metadata blob.
    # @return [Hash] created schedule.
    def create(source_id:, dataset_id:, cron:, timezone: nil, pipeline_id: nil, enabled: nil, name: nil, metadata: nil)
      body = {
        "source_id" => source_id,
        "dataset_id" => dataset_id,
        "cron" => cron,
      }
      body["timezone"] = timezone unless timezone.nil?
      body["pipeline_id"] = pipeline_id unless pipeline_id.nil?
      body["enabled"] = enabled unless enabled.nil?
      body["name"] = name unless name.nil?
      body["metadata"] = metadata unless metadata.nil?
      @transport.request(:post, "/ingestion/schedules", body: body)
    end

    # Update a schedule. Only non-nil fields are sent.
    # @param schedule_id [String]
    # @return [Hash] updated schedule.
    def update(schedule_id, cron: nil, timezone: nil, pipeline_id: nil, enabled: nil, name: nil, metadata: nil)
      body = {}
      body["cron"] = cron unless cron.nil?
      body["timezone"] = timezone unless timezone.nil?
      body["pipeline_id"] = pipeline_id unless pipeline_id.nil?
      body["enabled"] = enabled unless enabled.nil?
      body["name"] = name unless name.nil?
      body["metadata"] = metadata unless metadata.nil?
      @transport.request(:patch, "/ingestion/schedules/#{schedule_id}", body: body)
    end

    # Delete a schedule.
    # @param schedule_id [String]
    # @return [Hash] deletion confirmation envelope.
    def delete(schedule_id)
      @transport.request(:delete, "/ingestion/schedules/#{schedule_id}")
    end

    # Trigger an immediate run for a schedule, outside its cron cadence.
    # @param schedule_id [String]
    # @return [Hash] `{ "job_id" => "..." }` for the new ingestion job.
    def trigger(schedule_id)
      @transport.request(:post, "/ingestion/schedules/#{schedule_id}/trigger")
    end
  end
end
