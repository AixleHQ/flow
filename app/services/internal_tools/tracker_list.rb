# frozen_string_literal: true

module InternalTools
  class TrackerList < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: List Trackers"
      description "List the task trackers connected to this project: handle, provider, external project, whether it " \
                  "is primary, whether it is read-only, and whether it is usable now. Other tracker_* tools take the " \
                  "`handle` as `tracker` when the project has more than one. Returns JSON: {trackers: [{handle, " \
                  "provider, name, external_project, primary, access, usable, started_this_run}]}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      input_schema({ "type" => "object", "properties" => {}, "required" => [] })
    end

    def execute
      return error("This tool needs a project") if project.nil?

      pinned = workflow_run&.shared_context.to_h.dig("tracker", "project_tracker_id")
      trackers = ProjectTracker.for_project(project).where.not(status: :detached).includes(:integration).order(:id).map do |t|
        {
          handle: t.handle, provider: t.provider, name: t.name, external_project: t.external_scope_id,
          primary: t.primary, access: t.access, usable: t.usable?, started_this_run: t.id == pinned.to_i
        }
      end
      success({ trackers: trackers }.to_json)
    end
  end
end
