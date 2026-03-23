# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class ActivitiesController < Api::V1::Company::Projects::ApplicationController
              def index
                activities = current_task.board_activities.includes(:actor, :board_task).order(created_at: :desc)
                activities = activities.by_event_type(params[:event_type]) if params[:event_type].present?
                activities = activities.by_actor_type(params[:actor_type]) if params[:actor_type].present?
                activities = activities.since(Time.parse(params[:since])) if params[:since].present?
                respond_with paginate(activities), each_serializer: BoardActivitySerializer
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end
            end
          end
        end
      end
    end
  end
end
