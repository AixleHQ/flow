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

            def update
              comment = current_task.task_comments.find(params[:id])
              # update? and destroy? (the policy) are plain project-writes; the
              # record-level rules — own comment, human-authored, younger than
              # TaskComment::EDIT_WINDOW — live in the actions because the authorize-by-default
              # path hands the policy a symbol, not the record (see AuthorizationConcern).
              unless comment.editable_by?(current_user)
                return render json: { error: "Not authorized" }, status: :forbidden
              end

              comment = TaskService.update_comment(
                task: current_task, comment: comment, params: comment_params.slice(:body), actor: current_user
              )
              render json: TaskCommentResource.new(comment).to_h
            end

            def destroy
              comment = current_task.task_comments.find(params[:id])
              unless comment.deletable_by?(current_user)
                return render json: { error: "Not authorized" }, status: :forbidden
              end

              TaskService.destroy_comment(task: current_task, comment: comment, actor: current_user)
              head :no_content
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
