# frozen_string_literal: true

# A tracker user Aixle holds data about, by id. Atlassian requires apps that
# keep account ids to report them every cycle and erase what belongs to a
# closed account (Trackers::Jira::PersonalDataReporter).
class TrackerAccount < ApplicationRecord
  extend Enumerize

  enumerize :status, in: %i[active closed], default: :active, predicates: true

  validates :provider, :account_id, presence: true

  scope :for_provider, ->(provider) { where(provider: provider.to_s) }
  scope :due, ->(cycle) { where(status: "active").where(reported_at: nil).or(where(status: "active", reported_at: ...cycle.ago)) }

  def self.remember!(provider:, account_ids:)
    ids = Array(account_ids).map(&:to_s).compact_blank.uniq
    return if ids.empty?

    now = Time.current
    upsert_all(ids.map { |id| { provider: provider.to_s, account_id: id, first_seen_at: now, last_seen_at: now } },
               unique_by: %i[provider account_id], update_only: %i[last_seen_at])
  end
end
