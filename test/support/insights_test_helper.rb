# frozen_string_literal: true

# A project connected to Aixle Insights through its company, exported, and — unless asked
# otherwise — sharing prompts (docs/design/insights-usage-export.md §5).
module InsightsTestHelper
  def connect_to_insights!(project, share_prompts: true, insights_project_id: nil)
    integration = Integration.find_by(company: project.company, project: nil, provider: "insights") ||
                  create(:integration, :insights, company: project.company)
    project.update!(settings: project.settings.to_h.merge(
      "insights" => { "export" => true, "share_prompts" => share_prompts, "project_id" => insights_project_id }
    ))
    integration
  end
end
