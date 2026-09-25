# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class StepsController < Workflows::ApplicationController
          def index
            steps = current_workflow.steps.not_deleted.includes(:sub_steps)
            render json: steps.map { |s| StepResource.new(s).to_h }
          end

          def show
            step = current_workflow.steps.not_deleted.find(params[:id])
            render json: StepResource.new(step).to_h
          end

          def create
            step = current_workflow.steps.new(step_params)
            versioned { step.save! }
            render json: StepResource.new(step).to_h, status: :created
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          def update
            step = current_workflow.steps.not_deleted.find(params[:id])
            versioned { step.update!(step_params) }
            render json: StepResource.new(step).to_h
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          def destroy
            step = current_workflow.steps.not_deleted.find(params[:id])
            versioned { step.destroy }
            head :no_content
          end

          # @summary Reorder steps within a project workflow
          def reorder
            step_ids = current_workflow.steps.not_deleted.pluck(:id).map(&:to_s)
            positions = params.require(:positions).permit(*step_ids).to_h
            positions = positions.select { |k, v| k.match?(/\A\d+\z/) && v.to_s.match?(/\A\d+\z/) }

            ordered = positions.sort_by { |step_id, position| [ position.to_i, step_id.to_i ] }.map(&:first)
            versioned { Positions.reorder!(current_workflow.steps, ordered) }
            head :ok
          end
        end
      end
    end
  end
end
