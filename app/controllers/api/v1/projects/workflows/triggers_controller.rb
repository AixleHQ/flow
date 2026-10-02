# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        # CRUD for a workflow's triggers — the single home for "how this workflow
        # launches". Manages two record kinds behind one unified API:
        #   • column  → ColumnWorkflowBinding (a card entering a board column)
        #   • event   → TriggerBinding (slack / webhook / schedule / custom event)
        # A webhook trigger additionally provisions a generic WebhookEndpoint and
        # returns its URL + secret.
        class TriggersController < Workflows::ApplicationController
          def index
            render json: { triggers: serialized_triggers }
          end

          def create
            kind = params.dig(:trigger, :kind).to_s
            unless WorkflowTriggers::Creator::KINDS.include?(kind)
              return render json: { errors: [ "Unsupported trigger kind: #{kind}" ] }, status: :unprocessable_entity
            end

            result = WorkflowTriggers::Creator.call(
              project: current_project, workflow: current_workflow, user: current_user,
              kind: kind, attributes: creator_attributes(kind)
            )
            render json: serialize_result(result), status: :created
          rescue WorkflowTriggers::Creator::BoardMissingError
            render json: { errors: [ "This project has no board. Create a board before adding a column trigger." ] }, status: :unprocessable_entity
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          rescue Temporalio::Error => e
            # Schedule triggers reconcile onto Temporal synchronously on save; the
            # binding is persisted but scheduling failed. Surface it (the user can
            # re-save to retry; the worker-boot sync also re-reconciles).
            Rails.logger.error("[triggers] Temporal scheduling failed: #{e.message}")
            render json: { errors: [ "Trigger saved, but scheduling it failed — re-save to retry. (#{e.message})" ] }, status: :bad_gateway
          end

          def update
            case params[:kind].to_s
            when "column"
              binding = column_bindings.find(params[:id])
              binding.update!(column_binding_params)
              render json: serializer.column(binding)
            else
              binding = current_workflow.trigger_bindings.find(params[:id])
              binding.assign_attributes(trigger_binding_params)
              binding.save_checking_slack!
              render json: serialize_binding(binding)
            end
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          rescue Temporalio::Error => e
            # Schedule triggers reconcile onto Temporal synchronously on save; the
            # binding is persisted but scheduling failed. Surface it (the user can
            # re-save to retry; the worker-boot sync also re-reconciles).
            Rails.logger.error("[triggers] Temporal scheduling failed: #{e.message}")
            render json: { errors: [ "Trigger saved, but scheduling it failed — re-save to retry. (#{e.message})" ] }, status: :bad_gateway
          end

          def destroy
            case params[:kind].to_s
            when "column"
              column_bindings.find(params[:id]).destroy
            else
              current_workflow.trigger_bindings.find(params[:id]).destroy
            end
            head :no_content
          end

          private

          # ---- creation ----

          def creator_attributes(kind)
            trigger = params.require(:trigger)
            return trigger.permit(:board_column_id, :trigger_mode, :cooldown_seconds).to_h if kind == "column"

            trigger_binding_params.to_h.merge(trigger.permit(:event_type, :verification_strategy, :secret).to_h)
          end

          def serialize_result(result)
            return serializer.column(result.trigger) if result.kind == "column"

            endpoint = result.webhook_endpoint
            payload = serialize_binding(result.trigger, endpoint: endpoint)
            # The secret is shown once, on create.
            endpoint ? payload.merge(webhook_secret: endpoint.secret) : payload
          end

          # ---- params ----

          def trigger_binding_params
            params.require(:trigger).permit(
              :name, :trigger_mode, :enabled, :cooldown_seconds, :notify_on_failure,
              :subject_policy, :subject_column_id, :subject_title_template, :project_tracker_id, :aixle_changes,
              filter_predicate: {}, schedule_config: %i[cron timezone]
            )
          end

          def column_binding_params
            params.require(:trigger).permit(:trigger_mode, :cooldown_seconds)
          end

          # ---- serialization ----

          def serialized_triggers
            bindings = current_workflow.trigger_bindings.includes(:created_by, :workflow).order(:created_at).to_a
            event_serializer = WorkflowTriggers::Serializer.new(webhook_endpoints: WorkflowTriggers::Serializer.endpoints_for(bindings))
            column_bindings.includes(:board_column, :created_by, :workflow).map { |b| serializer.column(b) } +
              bindings.map { |b| event_serializer.binding(b) }
          end

          def serializer
            @serializer ||= WorkflowTriggers::Serializer.new
          end

          def serialize_binding(binding, endpoint: nil)
            endpoints = endpoint ? { binding.event_type => endpoint } : WorkflowTriggers::Serializer.endpoints_for([ binding ])
            WorkflowTriggers::Serializer.new(webhook_endpoints: endpoints).binding(binding)
          end

          def column_bindings
            ColumnWorkflowBinding
              .joins(board_column: :board)
              .where(boards: { project_id: current_project.id }, workflow_id: current_workflow.id)
          end
        end
      end
    end
  end
end
