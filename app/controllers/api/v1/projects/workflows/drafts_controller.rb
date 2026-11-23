# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        # A workflow's draft (docs/design/workflow-drafts.md), addressed through the
        # live workflow: open it (optionally with the builder's unsaved Save as its
        # first change), see what applying it would change, apply it, discard it.
        # The draft itself is edited through the workflow endpoints, by its own id.
        class DraftsController < Workflows::ApplicationController
          def create
            aggregate = params[:aggregate].present? ? AggregatesController.permitted(params) : nil
            existing = current_workflow.open_draft
            draft = WorkflowDrafts.open!(current_workflow, actor: version_actor, aggregate: aggregate)
            render json: { draftId: draft.id, url: draft_company_project_workflow_path(current_project, current_workflow) },
                   status: draft == existing ? :ok : :created
          rescue WorkflowDrafts::Error, WorkflowAggregateSave::Invalid => e
            render json: { errors: [ e.message ] }, status: :unprocessable_entity
          end

          # The snapshots are verbatim (snake_case keys), as EntityVersionDetailResource sends them.
          def changes
            result = WorkflowDrafts.changes(open_draft)
            render json: {
              live: result[:live], draft: result[:draft], references: result[:references],
              liveVersionNumber: result[:live_version_number], baseVersionNumber: result[:base_version_number],
              draftVersionNumber: result[:draft_version_number]
            }
          end

          def apply
            overwrite = ActiveModel::Type::Boolean.new.cast(params[:overwrite]) || false
            version = WorkflowDrafts.apply!(open_draft, actor: version_actor, overwrite: overwrite)
            render json: {
              currentVersionNumber: current_workflow.reload.current_version_number,
              versionCreated: version.present?,
              url: builder_company_project_workflow_path(current_project, current_workflow)
            }
          rescue WorkflowDrafts::LiveChanged => e
            render json: { error: e.message, baseVersionNumber: e.base_version, liveVersionNumber: e.live_version },
                   status: :conflict
          rescue WorkflowAggregateSave::Invalid => e
            render json: { errors: [ e.message ] }, status: :unprocessable_entity
          end

          def destroy
            WorkflowDrafts.discard!(open_draft, actor: version_actor)
            render json: { url: builder_company_project_workflow_path(current_project, current_workflow) }
          end

          private

          def open_draft
            current_workflow.open_draft or raise ActiveRecord::RecordNotFound
          end
        end
      end
    end
  end
end
