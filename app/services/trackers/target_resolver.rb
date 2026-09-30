# frozen_string_literal: true

module Trackers
  # Which of a project's trackers a tool call acts on
  # (docs/design/task-tracker-integrations.md §7.2). Deterministic: row order
  # never decides, and a run started by a tracker never falls back to another one.
  class TargetResolver
    def initialize(project:, workflow_run: nil)
      @project = project
      @workflow_run = workflow_run
    end

    def resolve!(requested: nil, ref: nil)
      raise Error.new("This tool needs a project", code: "no_project") if @project.nil?

      return explicit!(requested) if requested.present?
      return pinned! if pinned_id

      owner = owner_of(ref)
      return owner if owner

      usable = trackers.select(&:usable?)
      usable.find(&:primary?) || (usable.one? && usable.first) || ambiguous!(usable)
    end

    private

    def trackers
      @trackers ||= ProjectTracker.for_project(@project).where.not(status: :detached).includes(:integration).order(:id).to_a
    end

    def explicit!(requested)
      value = requested.to_s.strip.downcase
      tracker = trackers.find { |t| t.handle == value || t.id.to_s == value }
      raise Error.new("No tracker '#{requested}' in this project — tracker_list shows them", code: "not_found") unless tracker

      usable!(tracker)
    end

    def pinned_id
      @workflow_run&.shared_context.to_h.dig("tracker", "project_tracker_id")
    end

    def pinned!
      tracker = trackers.find { |t| t.id == pinned_id.to_i }
      unless tracker&.usable?
        raise Error.new("The tracker this run was started from is no longer connected", code: "tracker_unavailable")
      end

      tracker
    end

    def owner_of(ref)
      return if ref.blank?

      owners = trackers.select { |t| t.usable? && t.tracker_provider.owns_reference?(t.external_scope_id, ref) }
      owners.first if owners.one?
    end

    def usable!(tracker)
      return tracker if tracker.usable?

      raise Error.new("Tracker '#{tracker.handle}' is not usable right now — its connection is not active",
                      code: "tracker_unavailable")
    end

    def ambiguous!(usable)
      raise Error.new("No tracker is connected to this project", code: "no_tracker") if usable.empty?

      handles = usable.map(&:handle)
      raise Error.new("This project has several trackers and none is primary — pass `tracker`: #{handles.join(', ')}",
                      code: "tracker_required", details: { trackers: handles })
    end
  end
end
