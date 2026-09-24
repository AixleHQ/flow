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
              render json: serialize_column(binding)
            else
              binding = current_workflow.trigger_bindings.find(params[:id])
              binding.update!(trigger_binding_params)
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
            return serialize_column(result.trigger) if result.kind == "column"

            payload = serialize_binding(result.trigger)
            return payload unless result.webhook_endpoint

            payload.merge(
              webhook_url: webhook_url(result.webhook_endpoint.slug),
              webhook_secret: result.webhook_endpoint.secret,
              verification_strategy: result.webhook_endpoint.verification_strategy
            )
          end

          # ---- params ----

          def trigger_binding_params
            params.require(:trigger).permit(
              :name, :trigger_mode, :enabled, :cooldown_seconds, :notify_on_failure,
              :subject_policy, :subject_column_id, :subject_title_template,
              filter_predicate: {}, schedule_config: %i[cron timezone]
            )
          end

          def column_binding_params
            params.require(:trigger).permit(:trigger_mode, :cooldown_seconds)
          end

          # ---- serialization ----

          def serialized_triggers
            column_bindings.includes(:board_column, :created_by).map { |b| serialize_column(b) } +
              current_workflow.trigger_bindings.includes(:created_by).order(:created_at).map { |b| serialize_binding(b) }
          end

          def column_bindings
            ColumnWorkflowBinding
              .joins(board_column: :board)
              .where(boards: { project_id: current_project.id }, workflow_id: current_workflow.id)
          end

          def serialize_column(binding)
            {
              id: binding.id,
              kind: "column",
              event_type: "board.column_changed",
              board_column_id: binding.board_column_id,
              column_name: binding.board_column.name,
              trigger_mode: binding.trigger_mode,
              cooldown_seconds: binding.cooldown_seconds,
              created_by: serialize_creator(binding.created_by),
              enabled: true
            }
          end

          def serialize_binding(binding)
            {
              id: binding.id,
              kind: binding_kind(binding.event_type),
              event_type: binding.event_type,
              name: binding.name,
              filter_predicate: binding.filter_predicate,
              trigger_mode: binding.trigger_mode,
              subject_policy: binding.subject_policy,
              subject_column_id: binding.subject_column_id,
              subject_title_template: binding.subject_title_template,
              schedule_config: binding.schedule_config,
              cooldown_seconds: binding.cooldown_seconds,
              notify_on_failure: binding.notify_on_failure,
              created_by: serialize_creator(binding.created_by),
              enabled: binding.enabled
            }
          end

          # Who a trigger runs as. nil for rows created before the creator was
          # recorded (and for a deleted account, whose reference is nullified) —
          # the UI shows those as "Unknown" and an unattended fire is skipped.
          def serialize_creator(user)
            return nil unless user

            { id: user.id, name: user.name }
          end

          def binding_kind(event_type)
            case event_type
            when "slack.message" then "slack"
            when "schedule.fired" then "schedule"
            when /\Awebhook\./ then "webhook"
            else "event"
            end
          end

          def webhook_url(slug)
            "https://#{Settings.domain}/webhooks/in/#{slug}"
          end
        end
      end
    end
  end
end
