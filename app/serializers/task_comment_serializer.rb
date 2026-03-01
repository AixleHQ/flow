# frozen_string_literal: true

class TaskCommentSerializer < ApplicationSerializer
  attributes :id, :body, :author_id, :author_name, :author_type, :tags, :created_at

  def author_name
    object.author&.name
  end
end
