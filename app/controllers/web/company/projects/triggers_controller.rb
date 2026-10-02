# frozen_string_literal: true

# Every way a workflow of the project can start, in one list. The triggers
# themselves arrive over the JSON API (Api::V1::Projects::TriggersController),
# so their filter predicates keep their dotted keys; the props here are only
# what the form's pickers offer.
class Web::Company::Projects::TriggersController < Web::Company::Projects::ApplicationController
  def index
    render inertia: "Projects/Triggers/TriggersPage", props: {
      project: project_props,
      workflows: current_project.workflows.active.order(:name).map { |w| { id: w.id, name: w.name } },
      board_columns: current_project.board&.board_columns&.includes(column_workflow_binding: :workflow)&.order(:position)&.map { |c|
        { id: c.id, name: c.name, bound_workflow_name: c.column_workflow_binding&.workflow&.name }
      } || [],
      # Detached ones too: a trigger keeps the tracker it names through a detach.
      trackers: ProjectTracker.for_project(current_project).includes(:integration).order(:created_at).map { |t|
        { id: t.id, handle: t.handle, name: t.name, provider: t.provider, status: t.status,
          mentions_recognized: t.recognizes_mentions? }
      }
    }
  end
end
