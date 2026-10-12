# frozen_string_literal: true

module AixleInsights
  # Links a company to its Aixle Insights organization by storing the org's
  # ingest token on a company-wide Integration row (provider: aixle_insights,
  # project_id: nil), encrypted in `credentials`.
  #
  # Accept-on-save (decision [1b-1]): the collector returns 200 even for an
  # invalid token, so a connect-time probe can confirm reachability but never
  # validity. The token is saved and its real validity is observed when events
  # start arriving. Reconnecting replaces the token on the single row rather
  # than stacking a second connection (decision [1b-4]).
  class IntegrationService
    def initialize(company:, connected_by:)
      @company = company
      @connected_by = connected_by
    end

    # connect(ingest_token:) -> Integration
    #
    # A blank token yields an invalid (unsaved) record with a field error, so
    # the controller can surface it; a present token persists the active
    # company-wide row.
    def connect(ingest_token:)
      token = ingest_token.to_s.strip
      integration = Integration.find_or_initialize_by(
        company: @company, provider: :aixle_insights, project_id: nil
      )
      integration.name = "Aixle Insights"
      integration.connected_by = @connected_by
      integration.credentials_data = { "ingest_token" => token }
      integration.status = :active

      if token.blank?
        integration.errors.add(:ingest_token, "Enter the ingest token from Aixle Insights")
        return integration
      end

      integration.save!
      integration
    end
  end
end
