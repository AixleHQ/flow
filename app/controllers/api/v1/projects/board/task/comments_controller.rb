# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class CommentsController < Task::ApplicationController
            def index
              comments = current_task.task_comments.includes(:author).order(created_at: :desc)
              render json: comments.map { |c| TaskCommentResource.new(c).to_h }
            end

            def create
              comment = TaskService.add_comment(task: current_task, params: comment_params, actor: current_user)
              render json: TaskCommentResource.new(comment).to_h, status: :created
            end

            private

            def comment_params
              params.require(:task_comment).permit(:body, tags: [])
            end
          end
        end
      end
    end
  end
end
