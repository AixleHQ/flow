# frozen_string_literal: true

module Feedback
  # Makes each submission a card in one column of one project's board.
  class BoardDestination
    def self.configured? = settings.board_project_id.present? && settings.board_column_id.present?

    def self.settings = Settings.feedback

    def initialize(submission)
      @submission = submission
    end

    def deliver
      @submission.with_lock do
        next if @submission.board_delivered_at

        card = column.board.board_tasks.create!(
          board_column: column,
          title: report.title,
          description: description,
          task_type: @submission.kind == "bug" ? :bug : :not_specified,
          tags: [ "feedback", @submission.kind.dasherize ]
        )
        attach_files(card)
        @submission.update!(board_delivered_at: Time.current)
      end
    end

    private

    # A copy of each file, not a reference: archiving the card must not take the
    # submission's own file with it, nor the other way round.
    def attach_files(card)
      @submission.attachments.each do |attachment|
        asset = card.task_assets.build(name: attachment.name, author_type: :system)
        asset.file_attacher.attach(attachment.file)
        asset.save!
      end
    end

    def report = @report ||= Report.new(@submission)

    # Looked up across every company on purpose: the column is the operator's,
    # and the sender belongs to whichever company they work in.
    def column
      @column ||= begin
        settings = self.class.settings
        project = Project.find_by(id: settings.board_project_id)
        project&.board&.board_columns&.find_by(id: settings.board_column_id) ||
          raise(DeliveryRejected, "FEEDBACK_BOARD_COLUMN_ID is not a column on the board of FEEDBACK_BOARD_PROJECT_ID")
      end
    end

    def description
      rows = report.fields.map { |label, value| "| **#{label}** | #{cell(value)} |" }
      [ @submission.message, "", "| | |", "| --- | --- |", *rows ].join("\n")
    end

    def cell(value)
      value.to_s.gsub("|", "\\|").gsub(/\s*\n\s*/, " ")
    end
  end
end
