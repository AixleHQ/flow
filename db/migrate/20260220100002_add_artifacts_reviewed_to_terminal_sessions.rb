# frozen_string_literal: true

class AddArtifactsReviewedToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :terminal_sessions, :artifacts_reviewed, :boolean, default: false
  end
end
