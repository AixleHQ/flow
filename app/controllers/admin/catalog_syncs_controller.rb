# frozen_string_literal: true

module Admin
  # Manual triggers for the two catalog mirrors.
  #
  # WHY THIS EXISTS: both catalogs fill on a schedule (skills daily + weekly, MCP
  # connectors weekly), which means a fresh deployment shows an empty Connectors or
  # Skills page until the first run fires. Waiting up to a week for a browsable
  # catalog is not an acceptable first impression, and neither is SSH-ing in to run a
  # runner.
  #
  # The work is NOT done in the request: a sweep is a few hundred paced outbound
  # requests over minutes. This starts the same Temporal workflow the schedule starts,
  # so progress, retries and history are identical to a scheduled run.
  class CatalogSyncsController < Admin::ApplicationController
    CATALOGS = {
      "skills" => { workflow: "skills_catalog_sync_workflow", label: "Skills catalog" },
      "skills_demand" => { workflow: "skills_demand_sync_workflow", label: "Skills (demand terms)" },
      "connectors" => { workflow: "mcp_connector_catalog_sync_workflow", label: "MCP connector catalog" }
    }.freeze

    def index
      @catalogs = CATALOGS
      @skills_count = CatalogSkill.count
      @skills_described = CatalogSkill.where.not(description: nil).count
      @skills_synced_at = CatalogSkill.maximum(:registry_synced_at)
      @connectors_count = Connector.count
      @connectors_synced_at = Connector.maximum(:updated_at)
      @search_terms = CatalogSearchQuery.by_demand.limit(10)

      render layout: "administrate/application"
    end

    def create
      catalog = CATALOGS[params[:catalog].to_s]
      return redirect_to(admin_catalog_syncs_path, alert: "Unknown catalog") if catalog.blank?

      workflow = TemporalWorkflowRegistry.workflows[catalog[:workflow]]
      return redirect_to(admin_catalog_syncs_path, alert: "Workflow not registered") if workflow.blank?

      # A STABLE id, so Temporal itself refuses a second concurrent run rather than us
      # tracking one: two sweeps would duplicate every request and spend the same
      # rate-limited budget twice.
      result = TemporalService.start_workflow(workflow, {}, id: "#{catalog[:workflow]}-manual")

      if result[:ok]
        redirect_to admin_catalog_syncs_path, notice: "#{catalog[:label]} sync started (#{result[:workflow_id]})"
      else
        redirect_to admin_catalog_syncs_path,
                    alert: "Could not start #{catalog[:label]} sync — #{result[:error]}"
      end
    end
  end
end
