# frozen_string_literal: true

# Every write a pull_request_* tool makes, recorded before the provider call
# (docs/design/bitbucket-integration.md §4.8).
#
# The unique (integration_id, operation_key) index serializes a retried call, and
# `unknown` records a request that left Aixle and was never answered — the next
# call with that key has to look before it writes again. The run, workflow and
# session that made the write are kept so a later pull-request event can be
# attributed to the run that caused it.
class PullRequestOperation < ApplicationRecord
  extend Enumerize

  enumerize :state, in: %i[pending succeeded failed unknown], default: :pending, predicates: true, scope: true

  belongs_to :integration
  belongs_to :repository

  validates :operation, presence: true
  validates :operation_key, presence: true, length: { maximum: 200 }
  validates :request_digest, presence: true

  class Conflict < StandardError; end

  class << self
    # Returns [record, :claimed | :replayed]; raises Conflict when the key was
    # already spent on a different request.
    def claim!(integration:, repository:, key:, operation:, payload:, **attributes)
      digest = digest_for(payload)
      record = create!(integration: integration, repository: repository, operation_key: key, operation: operation,
                       request_digest: digest, state: :pending, **attributes)
      [ record, :claimed ]
    rescue ActiveRecord::RecordNotUnique
      record = find_by!(integration_id: integration.id, operation_key: key)
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

  def succeed!(result, pull_request_number: nil)
    update!(state: :succeeded, result: result.as_json, error_code: nil,
            pull_request_number: pull_request_number&.to_s || self.pull_request_number)
  end

  def fail!(error_code)
    update!(state: :failed, error_code: error_code.to_s)
  end

  def unknown!
    update!(state: :unknown, error_code: "outcome_unknown")
  end

  # Before a refused or unanswered write is sent again.
  def retry!
    update!(state: :pending, error_code: nil)
  end
end
