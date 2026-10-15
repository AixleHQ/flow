# frozen_string_literal: true

module Insights
  # Stores a project's Insights ingest token on its single project-scoped
  # Integration row. The token is encrypted through Integration#credentials_data=.
  class IntegrationService
    def initialize(project:, connected_by:)
      @project = project
      @connected_by = connected_by
    end

    def connect(ingest_token:)
      token = ingest_token.to_s.strip
      integration = Integration.find_or_initialize_by(
        company: @project.company, project: @project, provider: :insights
      )
      integration.name = "Insights"
      integration.connected_by = @connected_by
      integration.credentials_data = { "ingest_token" => token }
      integration.status = :active

      if token.blank?
        integration.errors.add(:ingest_token, "Enter the ingest token from Insights")
        return integration
      end

      integration.save!
      integration
    end
  end
end
