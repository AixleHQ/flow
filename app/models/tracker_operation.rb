# frozen_string_literal: true

# Every write a tracker_* tool makes, recorded before the provider call.
#
# Two jobs. Idempotency, as azure_devops_operations does for Azure pull
# requests: the unique (project_tracker_id, operation_key) index serializes a
# retried call, and `unknown` records a request that left Aixle and was never
# answered. And causality: the run, workflow and chain that made the write, so
# the tracker event it causes can be attributed back to that run
# (docs/design/task-tracker-integrations.md §6.6).
class TrackerOperation < ApplicationRecord
  extend Enumerize

  enumerize :state, in: %i[pending succeeded failed unknown], default: :pending, predicates: true, scope: true

  belongs_to :project_tracker

  validates :operation, presence: true
  validates :operation_key, presence: true, length: { maximum: 200 }
  validates :request_digest, presence: true

  class Conflict < StandardError; end

  class << self
    # Returns [record, :claimed | :replayed]; raises Conflict when the key was
    # already spent on a different request.
    def claim!(project_tracker:, key:, operation:, payload:, **attributes)
      digest = digest_for(payload)
      record = create!(project_tracker: project_tracker, operation_key: key, operation: operation,
                       request_digest: digest, state: :pending, **attributes)
      [ record, :claimed ]
    rescue ActiveRecord::RecordNotUnique
      record = find_by!(project_tracker_id: project_tracker.id, operation_key: key)
      raise Conflict, "operation_key #{key} was already used for a different request" if record.request_digest != digest
      raise Conflict, "operation_key #{key} was used for #{record.operation}" if record.operation != operation

      [ record, :replayed ]
    end

    def digest_for(payload)
      Digest::SHA256.hexdigest(canonicalize(payload).to_json)
    end

    private

    def canonicalize(value)
      case value
      when Hash  then value.sort_by { |k, _| k.to_s }.to_h { |k, v| [ k.to_s, canonicalize(v) ] }
      when Array then value.map { |v| canonicalize(v) }
      else value
      end
    end
  end

  def succeed!(result, result_ref: nil)
    update!(state: :succeeded, result: result.as_json, result_ref: result_ref&.to_s, error_code: nil)
  end

  def fail!(error_code)
    update!(state: :failed, error_code: error_code.to_s)
  end

  def unknown!(error_code = "outcome_unknown")
    update!(state: :unknown, error_code: error_code.to_s)
  end
end
