# frozen_string_literal: true

# One recorded agent mutation against Azure DevOps, keyed by the caller's
# `operation_key`.
#
# Azure offers no idempotency key of its own, so "the agent called
# create_pull_request twice" and "the agent called it once and the response was
# lost" are indistinguishable upstream. This row makes them distinguishable
# here: the unique (integration_id, operation_key) index serializes duplicate
# submissions, `request_digest` turns the same key with a different payload into
# a conflict rather than a silent replay, and `unknown` records the one honest
# answer for a request that was dispatched and never answered.
class AzureDevopsOperation < ApplicationRecord
  extend Enumerize

  # pending    — claimed, request not yet known to have completed
  # succeeded  — provider confirmed, `result` holds the identifiers
  # failed     — provider rejected it; safe to report as not done
  # unknown    — dispatched, outcome never observed. NOT failed: reissuing it
  #              blindly is what creates duplicate pull requests and comments.
  enumerize :state, in: %i[pending succeeded failed unknown], default: :pending, predicates: true, scope: true

  belongs_to :integration
  belongs_to :terminal_session, class_name: "TerminalSession", optional: true
  belongs_to :user, optional: true

  validates :operation_key, presence: true, length: { maximum: 200 }
  validates :operation, presence: true
  validates :request_digest, presence: true

  scope :stale_pending, ->(age) { pending.where(created_at: ...age.ago) }

  class Conflict < StandardError; end

  class << self
    # Claim `key` for `operation`, or return the existing record for it.
    #
    # Returns [record, :claimed | :replayed]. `:claimed` means the caller owns
    # the upstream request and must finish the record; `:replayed` means someone
    # already did, and the caller reports that outcome instead of re-issuing.
    # Raises Conflict when the same key arrives with a different payload.
    def claim!(integration:, key:, operation:, payload:, session: nil, user: nil)
      digest = digest_for(payload)

      begin
        record = create!(
          integration: integration, operation_key: key, operation: operation,
          request_digest: digest, terminal_session: session, user: user, state: :pending
        )
        [ record, :claimed ]
      rescue ActiveRecord::RecordNotUnique
        record = find_by!(integration_id: integration.id, operation_key: key)
        if record.request_digest != digest
          raise Conflict, "operation_key #{key} was already used for a different request"
        end
        raise Conflict, "operation_key #{key} was used for #{record.operation}" if record.operation != operation

        [ record, :replayed ]
      end
    end

    # Stable across key ordering and Ruby hash iteration, so a retry that
    # rebuilds the same arguments hashes identically.
    def digest_for(payload)
      Digest::SHA256.hexdigest(canonicalize(payload).to_json)
    end

    def canonicalize(value)
      case value
      when Hash  then value.sort_by { |k, _| k.to_s }.to_h { |k, v| [ k.to_s, canonicalize(v) ] }
      when Array then value.map { |v| canonicalize(v) }
      else value
      end
    end
  end

  def succeed!(result, target_kind: nil, target_id: nil)
    update!(state: :succeeded, result: result.as_json, target_kind: target_kind,
            target_id: target_id&.to_s, error_code: nil)
  end

  def fail!(error_code)
    update!(state: :failed, error_code: error_code.to_s)
  end

  # The request left Aixle and its outcome was never observed. Recorded rather
  # than retried: the recovery path is a read against Azure, not another write.
  def unknown!(error_code = "outcome_unknown")
    update!(state: :unknown, error_code: error_code.to_s)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[operation operation_key state created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[integration terminal_session user]
  end
end
