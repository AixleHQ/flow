# frozen_string_literal: true

module Insights
  # What Flow knows about a session, as OTLP resource attributes
  # (docs/design/insights-otlp-relay.md §4). Unknown values are left out, never sent empty.
  class Metadata
    def initialize(session)
      @session = session
      @project = session.project
    end

    def attributes
      to_h.filter_map { |key, value| { "key" => key, "value" => otlp_value(value) } unless value.nil? }
    end

    def to_h
      settings = @project&.insights_settings || {}
      {
        "aixle_flow.version" => Settings.app.version.to_s.presence,
        "aixle_flow.company.id" => @session.company_id || @project&.company_id,
        "aixle_flow.project.id" => @project&.id,
        "aixle_flow.project.name" => @project&.name,
        "aixle_flow.session.id" => @session.id,
        "aixle_flow.session.type" => @session.session_type,
        "aixle_flow.workflow_run.id" => @session.step_run&.workflow_run_id,
        "aixle_flow.step_run.id" => @session.step_run&.id,
        "aixle_flow.agent.type" => @session.agent_type,
        "user.email" => @session.user&.email,
        "insights.project.id" => settings["project_id"].presence,
        "vcs.repository.url.full" => repository_url
      }
    end

    private

    # The session's own repository when it has exactly one, else the project's. Without
    # userinfo: Azure DevOps clone URLs carry the organization there, and nothing in a URL's
    # credential part is Insights' to see.
    def repository_url
      url = single_url(@session.repositories) || single_url(@project&.repositories)
      url&.sub(%r{\A([a-z][a-z0-9+.-]*://)[^/@]*@}i, '\1')
    end

    def single_url(scope)
      urls = scope&.limit(2)&.pluck(:clone_url)
      urls.first if urls&.size == 1
    end

    # OTLP JSON writes an int64 as a string.
    def otlp_value(value)
      case value
      when Integer then { "intValue" => value.to_s }
      else { "stringValue" => value.to_s }
      end
    end
  end
end
