# frozen_string_literal: true

module Coder
  # QuarantineService — short-lived "this workspace is sick" markers.
  #
  # Stored in `integration_data` as `coder:workspace_health:<workspace_name>`,
  # the same table, TTL semantics and `(integration_id, key)` isolation the
  # lock service uses — so no migration, and the existing expired-row sweep
  # keeps it tidy.
  #
  # A marker is written only for evidence about that specific workspace (it did
  # not answer, it is overloaded, its remote command failed). Faults on our side
  # never write one — see `Coder::HealthCheck` and § D-0 of the design doc. The
  # cooldown is deliberately short and the allocator still falls back to a
  # quarantined box when nothing better exists, so the worst case is a healthy
  # workspace being passed over for one cooldown window.
  class QuarantineService
    KEY_PREFIX = "coder:workspace_health:"

    def initialize(integration)
      @integration = integration
    end

    def quarantine(workspace_name:, reason:, minutes: cooldown_minutes)
      row = @integration.integration_data.find_or_initialize_by(key: key_for(workspace_name))
      row.value = {
        "kind"        => "workspace_health",
        "state"       => "sick",
        "reason"      => reason.to_s,
        "observed_at" => Time.current.iso8601
      }
      row.expires_at = Time.current + minutes.minutes
      row.save!
      row
    end

    def clear(workspace_name:)
      @integration.integration_data.where(key: key_for(workspace_name)).delete_all
    end

    def quarantined?(workspace_name:)
      live.exists?(key: key_for(workspace_name))
    end

    # `{ "aixle-prod-1" => "load average 84.3 over 8.0 (4 cores)" }`
    def reasons
      live.each_with_object({}) do |row, acc|
        acc[row.key.delete_prefix(KEY_PREFIX)] = row.value["reason"].to_s
      end
    end

    def live
      @integration.integration_data.with_key_prefix(KEY_PREFIX).live
    end

    private

    def key_for(workspace_name)
      "#{KEY_PREFIX}#{workspace_name}"
    end

    def cooldown_minutes
      minutes = (Settings.coder&.unhealthy_cooldown_minutes || 30).to_i
      minutes.positive? ? minutes : 30
    end
  end
end
