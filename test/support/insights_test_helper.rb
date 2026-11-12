# frozen_string_literal: true

# A project connected to Aixle Insights through its company, and exported
# (docs/design/insights-otlp-relay.md §3).
module InsightsTestHelper
  def connect_to_insights!(project, insights_project_id: nil)
    integration = Integration.find_by(company: project.company, project: nil, provider: "insights") ||
                  create(:integration, :insights, company: project.company)
    project.update!(settings: project.settings.to_h.merge(
      "insights" => { "export" => true, "project_id" => insights_project_id }
    ))
    integration
  end
end
