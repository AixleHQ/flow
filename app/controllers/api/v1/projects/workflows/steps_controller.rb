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
            step.save!
            render json: StepResource.new(step).to_h, status: :created
          end

          def update
            step = current_workflow.steps.not_deleted.find(params[:id])
            step.update!(step_params)
            render json: StepResource.new(step).to_h
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          def destroy
            step = current_workflow.steps.not_deleted.find(params[:id])
            step.destroy
            head :no_content
          end

          # @summary Reorder steps within a project workflow
          def reorder
            # permit! is intentional here: keys are step IDs (validated below as integers)
            positions = params.require(:positions).permit!.to_h
            positions = positions.select { |k, v| k.match?(/\A\d+\z/) && v.to_s.match?(/\A\d+\z/) }

            ActiveRecord::Base.transaction do
              current_workflow.steps.update_all("position = position + 10000")
              positions.each do |step_id, new_position|
                current_workflow.steps.not_deleted.find(step_id).update_column(:position, new_position.to_i)
              end
            end
            head :ok
          end
        end
      end
    end
  end
end
