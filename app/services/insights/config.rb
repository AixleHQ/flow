# frozen_string_literal: true

module Insights
  module Config
    module_function

    # The integration exists only on a deployment Insights registered: its URL, id and secret.
    def enabled?
      settings = Settings.insights
      settings.present? && [ settings.url, settings.deployment_id, settings.deployment_secret ].all?(&:present?)
    end

    # Off, Insights' answer to a batch is final: what it refused or failed to take is let go.
    def resend? = Settings.insights&.resend == true
  end
end
