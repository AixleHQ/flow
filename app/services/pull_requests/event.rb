# frozen_string_literal: true

module PullRequests
  # What a code host says happened on a pull request, reduced to what triggers
  # match on and what an agent is shown (docs/design/pull-request-triggers.md §3).
  #
  # kind     — :review_submitted | :comment_created
  # verdict  — a review's outcome: approved | changes_requested | commented
  # actor    — { id:, name: } of the reviewer or commenter
  # own      — written by the connection's own account (an app's bot), so by Aixle
  # revision — what tells two deliveries of one change apart when there is no comment id
  Event = Data.define(:kind, :number, :title, :url, :source_branch, :target_branch, :author, :actor, :own,
                      :verdict, :body, :comment_id, :file, :line, :reply_to, :revision, :occurred_at) do
    def self.build(kind:, number:, actor: {}, own: false, **attributes)
      new(kind: kind.to_sym, number: number.to_i, actor: actor.to_h.symbolize_keys.compact_blank, own: own == true,
          **members.index_with(nil).except(:kind, :number, :actor, :own).merge(attributes))
    end

    # Jobs take plain values only.
    def self.from_job(values)
      values = values.to_h.symbolize_keys
      build(**values.slice(*members).merge(actor: values[:actor].to_h))
    end

    def to_job
      to_h.merge(kind: kind.to_s, actor: actor.transform_keys(&:to_s)).deep_stringify_keys
    end

    def review? = kind == :review_submitted
    def comment? = kind == :comment_created
  end
end
