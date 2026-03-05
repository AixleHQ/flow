# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class CommentsController < Api::V1::Company::Projects::ApplicationController
              def index
                comments = current_task.task_comments.order(created_at: :desc)
                comments = comments.with_tag(params[:tag]) if params[:tag].present?
                comments = comments.by_author_type(params[:author_type]) if params[:author_type].present?
                respond_with comments, each_serializer: TaskCommentSerializer
              end

              def create
                comment = current_task.task_comments.build(comment_params)
                comment.author = current_user
                comment.author_type = :human
                if comment.save
                  ActivityRecorder.record(
                    board: current_board, event_type: :comment_added, actor: current_user,
                    actor_type: :human, task: current_task,
                    metadata: { tag: comment.tags&.first, preview: comment.body.to_s.truncate(100) }
                  )
                end
                respond_with comment, serializer: TaskCommentSerializer
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end

              def comment_params
                params.require(:task_comment).permit(:body, tags: [])
              end
            end
          end
        end
      end
    end
  end
end
