# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class ActivitiesController < Board::ApplicationController
          include PaginationConcern

          def index
            activities = current_board.board_activities.includes(:actor, :board_task).order(created_at: :desc)
            activities = activities.by_event_type(params[:event_type]) if params[:event_type].present?
            activities = activities.by_actor_type(params[:actor_type]) if params[:actor_type].present?
            activities = activities.since(Time.parse(params[:since])) if params[:since].present?
            pagy, records = paginate(activities)
            render json: PaginatedResource.build(pagy, records) { |a| BoardActivityResource.new(a).to_h }
          end
        end
      end
    end
  end
end
