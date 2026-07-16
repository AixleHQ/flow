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
            result =
              case kind
              when "column" then create_column_trigger
              when "webhook" then create_webhook_trigger
              when "slack", "schedule", "event" then create_event_trigger(kind)
              else return render json: { errors: [ "Unsupported trigger kind: #{kind}" ] }, status: :unprocessable_entity
              end

            render json: result, status: :created
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

          # ---- creators ----

          def create_column_trigger
            column = current_project.board.board_columns.find(params.dig(:trigger, :board_column_id))
            binding = ColumnWorkflowBinding.create!(
              board_column: column,
              workflow: current_workflow,
              trigger_mode: params.dig(:trigger, :trigger_mode).presence || "auto",
              cooldown_seconds: params.dig(:trigger, :cooldown_seconds).presence || 5
            )
            serialize_column(binding)
          end

          def create_event_trigger(kind)
            event_type =
              case kind
              when "slack"    then "slack.message"
              when "schedule" then "schedule.fired"
              else params.dig(:trigger, :event_type).to_s.presence || "webhook.received"
              end
            binding = current_workflow.trigger_bindings.create!(
              trigger_binding_params.merge(project: current_project, created_by: current_user, event_type: event_type)
            )
            serialize_binding(binding)
          end

          def create_webhook_trigger
            token = SecureRandom.hex(6)
            event_type = "webhook.#{token}"
            endpoint = WebhookEndpoint.create!(
              slug: "wh-#{token}",
              provider: :generic,
              verification_strategy: params.dig(:trigger, :verification_strategy).presence || "none",
              secret: params.dig(:trigger, :secret).presence,
              config: { "event_type" => event_type },
              project: current_project,
              company: current_project.company,
              created_by: current_user
            )
            binding = current_workflow.trigger_bindings.create!(
              trigger_binding_params.merge(project: current_project, created_by: current_user, event_type: event_type)
            )
            serialize_binding(binding).merge(
              webhook_url: webhook_url(endpoint.slug),
              webhook_secret: endpoint.secret,
              verification_strategy: endpoint.verification_strategy
            )
          end

          # ---- params ----

          def trigger_binding_params
            params.require(:trigger).permit(
              :name, :trigger_mode, :enabled, :cooldown_seconds,
              :subject_policy, :subject_column_id, :subject_title_template,
              filter_predicate: {}, schedule_config: %i[cron timezone]
            )
          end

          def column_binding_params
            params.require(:trigger).permit(:trigger_mode, :cooldown_seconds)
          end

          # ---- serialization ----

          def serialized_triggers
            column_bindings.map { |b| serialize_column(b) } +
              current_workflow.trigger_bindings.order(:created_at).map { |b| serialize_binding(b) }
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
              enabled: binding.enabled
            }
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
