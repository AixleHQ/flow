# frozen_string_literal: true

class Web::Company::Projects::TrackersController < Web::Company::Projects::ApplicationController
  def index
    trackers = ProjectTracker.for_project(current_project).includes(:integration).order(:created_at)

    render inertia: "Projects/Trackers/TrackersPage", props: {
      project: project_props,
      trackers: trackers.map { |t| ProjectTrackerResource.new(t).to_h },
      available_scopes: available_scopes(trackers),
      triggers: tracker_triggers,
      # For the one-column intake shortcut, which wires a tracker trigger to a
      # workflow and a board column for its tasks.
      workflows: Workflow.visible_for_project(current_project).where(deleted_at: nil).order(:name)
                         .map { |w| { id: w.id, name: w.name } },
      board_columns: current_project.board&.board_columns&.order(:position)&.map { |c| { id: c.id, name: c.name } } || []
    }
  end

  def create
    integration = tracker_integrations.find_by(id: create_params[:integration_id])
    scope = integration && Trackers::Provider.for(integration).scopes.find { |s| s.id == create_params[:external_scope_id].to_s }
    return redirect_back_with_errors(external_scope_id: "Pick a project this connection covers") unless scope

    tracker = ProjectTracker.new(
      project: current_project, integration: integration, external_scope_id: scope.id, external_scope_key: scope.key,
      name: scope.name, access: create_params[:access].presence || "read_write",
      handle: create_params[:handle].presence || ProjectTracker.handle_for(scope.name, taken: taken_handles)
    )
    return redirect_back_with_errors(tracker.errors) unless tracker.save

    tracker.make_primary! if create_params[:primary].to_s == "true" || !ProjectTracker.for_project(current_project).exists?(primary: true)
    redirect_to company_project_trackers_path(current_project), notice: "Tracker added"
  end

  def update
    tracker = ProjectTracker.for_project(current_project).find(params[:id])
    attributes = update_params.slice(:handle, :access).compact_blank
    return redirect_back_with_errors(tracker.errors) unless tracker.update(attributes)

    if update_params[:status] == "active" && tracker.detached?
      refusal = reattach_refusal(tracker)
      return redirect_back_with_errors(status: refusal) if refusal
    end
    tracker.make_primary! if update_params[:primary].to_s == "true" && !tracker.detached?
    redirect_to company_project_trackers_path(current_project), notice: "Tracker updated"
  end

  def destroy
    ProjectTracker.for_project(current_project).find(params[:id]).detach!
    redirect_to company_project_trackers_path(current_project), notice: "Tracker detached"
  end

  # The statuses a trigger can filter on — the columns of the tracker's board.
  # JSON, like the Azure connect endpoints: the pickers ask for it on demand.
  def statuses
    tracker = ProjectTracker.for_project(current_project).find(params[:id])
    description = tracker.tracker_provider.describe(tracker.external_scope_id)
    render json: { statuses: description[:statuses].map { |s| { name: s.name, category: s.category } } }
  rescue Trackers::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def tracker_integrations
    Integration.visible_for_project(current_project).active.where(provider: Trackers::PROVIDERS.keys)
  end

  # The project's tracker triggers, for the row of the tracker each one listens
  # to; one with no tracker listens to all of them. The filter goes out as the
  # statuses and the mention switch the trigger form edits, not as the raw
  # predicate, whose dotted keys the prop camelizer would rewrite.
  def tracker_triggers
    TriggerBinding.where(project_id: current_project.id, event_type: Trackers::EventPipeline::EVENT_TYPES)
                  .joins(:workflow).merge(Workflow.active).includes(:workflow).order(:id)
                  .map do |binding|
      filter = binding.filter_predicate.to_h
      status = filter["change.to.name"]
      {
        id: binding.id, workflow_id: binding.workflow_id, workflow_name: binding.workflow.name,
        project_tracker_id: binding.project_tracker_id, event_type: binding.event_type, enabled: binding.enabled,
        statuses: status.is_a?(Hash) && status["op"] == "in" ? Array(status["value"]) : [],
        mentions_only: filter["comment.mentions_me"] == true
      }
    end
  end

  # Each connection's external projects that are not mapped into this project yet.
  def available_scopes(trackers)
    mapped = trackers.to_set { |t| [ t.integration_id, t.external_scope_id ] }
    tracker_integrations.filter_map do |integration|
      provider = Trackers::Provider.for(integration)
      next unless provider.serves_project?(current_project)

      scopes = provider.scopes.reject { |s| mapped.include?([ integration.id, s.id ]) }
      next if scopes.empty?

      { integration_id: integration.id, integration_name: integration.name, provider: integration.provider.to_s,
        scopes: scopes.map { |s| { id: s.id, name: s.name } } }
    end
  end

  def taken_handles
    ProjectTracker.for_project(current_project).pluck(:handle)
  end

  def reattach_refusal(tracker)
    tracker.reattach!
    nil
  rescue ActiveRecord::RecordInvalid
    return tracker.errors.full_messages.to_sentence unless tracker.errors.include?(:external_scope_id)

    "#{tracker.integration.name} no longer covers #{tracker.name}. Add it to the connection on the " \
      "Integrations page, then attach it again."
  end

  def redirect_back_with_errors(errors)
    errors = errors.to_hash(true).transform_values(&:to_sentence) if errors.is_a?(ActiveModel::Errors)
    redirect_to company_project_trackers_path(current_project), inertia: { errors: errors }
  end

  def create_params
    params.require(:tracker).permit(:integration_id, :external_scope_id, :handle, :access, :primary)
  end

  def update_params
    params.require(:tracker).permit(:handle, :access, :primary, :status)
  end
end
