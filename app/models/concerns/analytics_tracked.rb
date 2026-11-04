# frozen_string_literal: true

# Product analytics for changes a person makes, whichever door they came in by:
# the web UI and the Flow MCP server both reach these models, and both set who
# is acting (Current.analytics_actor). A change nobody made in person (a job, a
# trigger) reports nothing. Analytics.track does the rest; this only says which
# company and project an event belongs to.
module AnalyticsTracked
  extend ActiveSupport::Concern

  private

  # Props may be a block, so what costs a query is only worked out when the
  # event will actually be sent.
  def report_analytics(event, props = {})
    return if Current.analytics_actor.nil? || !Analytics.enabled?

    project = analytics_project
    company = project&.company || analytics_company
    return if company.nil?

    Analytics.track(event, company: company, project: project, props: block_given? ? yield : props)
  end

  def analytics_project
    id = self[:project_id] if has_attribute?(:project_id)
    id && Project.find_by(id: id)
  end

  def analytics_company
    id = self[:company_id] if has_attribute?(:company_id)
    id && Company.find_by(id: id)
  end

  def analytics_created_via
    Current.analytics_origin || Current.analytics_via
  end
end
