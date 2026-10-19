# frozen_string_literal: true

module Admin
  # The tenant report: what every company used, and whether it is billed for it
  # (docs/design/tenant-usage-report.md). An Administrate page with a React
  # island in it, fed the daily rows once.
  class TenantUsagesController < Admin::ApplicationController
    ROLLUP_WORKFLOW = "usage_rollup_workflow"

    def show
      @report = Usage::TenantReport.new.to_h.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      render layout: "administrate/application"
    end

    # Measures every hour since a date again. The schedule only revisits the last
    # few, so this is how history is filled in after a deploy, or rebuilt after a
    # fix. The work runs in the same workflow the schedule starts, under a stable
    # id, so a second click while one runs is refused by Temporal.
    def recompute
      since = Date.iso8601(params[:since].to_s)
      workflow = TemporalWorkflowRegistry.workflows[ROLLUP_WORKFLOW]
      result = TemporalService.start_workflow(workflow, { from_hour: since.to_time(:utc).iso8601 },
                                              id: "#{ROLLUP_WORKFLOW}-recompute")

      if result[:ok]
        redirect_to admin_tenant_usage_path, notice: "Recomputing usage since #{since.iso8601} (#{result[:workflow_id]})"
      else
        redirect_to admin_tenant_usage_path, alert: "Could not start the recompute — #{result[:error]}"
      end
    rescue Date::Error
      redirect_to admin_tenant_usage_path, alert: "Pick the date to recompute from"
    end
  end
end
