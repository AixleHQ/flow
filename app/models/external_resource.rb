# frozen_string_literal: true

# A board task's link to an object in an external system — for trackers, the
# issue a task is about. Identity is the external system's own
# (provider, instance, external_id), never the connection that saw it, so a link
# survives a reconnect or a second connection to the same tracker.
class ExternalResource < ApplicationRecord
  TRACKER_ISSUE = "tracker_issue"

  belongs_to :board_task

  validates :kind, :provider, :instance, :external_id, presence: true
  validates :external_id, uniqueness: { scope: %i[board_task_id kind provider instance] }

  scope :tracker_issues, -> { where(kind: TRACKER_ISSUE) }
  scope :identifying, ->(provider:, instance:, external_id:) {
    tracker_issues.where(provider: provider.to_s, instance: instance.to_s, external_id: external_id.to_s)
  }

  def key = data["key"]
  def url = data["url"]
end
