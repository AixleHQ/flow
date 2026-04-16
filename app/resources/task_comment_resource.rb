# frozen_string_literal: true

class TaskCommentResource < ApplicationResource
  attributes :id, :body, :author_id, :author_type, :tags, :created_at

  attribute :author_name do |comment|
    comment.author&.name
  end
end
