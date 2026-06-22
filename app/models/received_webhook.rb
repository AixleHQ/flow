# frozen_string_literal: true

# A single inbound webhook delivery, stored for idempotency (the unique
# endpoint+idempotency_key index) and as a raw audit/replay record before it is
# normalized into a TriggerEvent by Webhooks::ProcessEventJob.
class ReceivedWebhook < ApplicationRecord
  belongs_to :webhook_endpoint

  validates :idempotency_key, presence: true

  STATUSES = %w[received processed skipped failed].freeze
end
