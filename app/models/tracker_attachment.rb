# frozen_string_literal: true

# A file on a tracker issue that this project copied onto a board task
# (`imported`) or put onto the issue itself (`exported`). Keyed by the
# tracker's own identity of the file, per project, so a copy is made once and a
# file is not sent twice (docs/design/tracker-attachments.md §5).
#
# `data` holds what the tracker said about the file — name, size, content type,
# the issue's readable key — and never a signed URL or an author account id.
class TrackerAttachment < ApplicationRecord
  extend Enumerize

  # The id a file gets when it exists only as a URL in an issue's text.
  def self.embedded_id(url) = "url:#{Digest::SHA256.hexdigest(url.to_s)[0, 32]}"

  enumerize :direction, in: %i[imported exported], predicates: true

  belongs_to :project
  belongs_to :task_asset, optional: true

  validates :provider, :instance, :issue_id, :external_id, :content_sha256, presence: true
  validates :external_id, uniqueness: { scope: %i[project_id provider instance issue_id] }

  scope :on_issue, ->(project:, provider:, instance:, issue_id:) {
    where(project_id: project.id, provider: provider.to_s, instance: instance.to_s, issue_id: issue_id.to_s)
  }

  def name = data["name"]
  def issue_key = data["issue_key"]
end
