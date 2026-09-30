# frozen_string_literal: true

module Trackers
  # What a provider delivery says happened, reduced to identifiers and change
  # hints. The issue itself is re-read before anything is matched or shown.
  #
  # kind      — :issue_created | :issue_updated | :comment_created
  # changes   — [{ field: "status" | "assignee", from:, to: }]
  # actor     — { id:, name: } of whoever made the change, when the provider says
  # revision  — the provider's own discriminator for this change (Azure: rev)
  Notification = Data.define(:kind, :scope_id, :issue_id, :comment_id, :comment_text, :changes, :actor,
                             :revision, :occurred_at) do
    def self.build(kind:, scope_id:, issue_id:, comment_id: nil, comment_text: nil, changes: [], actor: {},
                   revision: nil, occurred_at: nil)
      new(kind:, scope_id: scope_id.to_s, issue_id: issue_id.to_s, comment_id:, comment_text:, changes:, actor:,
          revision:, occurred_at:)
    end
  end
end
