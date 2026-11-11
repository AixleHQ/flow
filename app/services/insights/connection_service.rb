# frozen_string_literal: true

module Insights
  # A company's connection to one Insights organization (docs/design/insights-usage-export.md
  # §5): made by redeeming an owner's pairing code, rotated in one call, removed only once
  # Insights confirms. The connection's secret lives in the integration's encrypted
  # credentials and is never shown.
  class ConnectionService
    class Error < StandardError; end

    def initialize(client: Client.build)
      @client = client
    end

    def connect(company:, user:, code:)
      raise Error, "Aixle Insights is not configured on this deployment" unless Config.enabled?
      raise Error, "Enter the pairing code from Insights" if code.to_s.strip.empty?

      existing = Integration.find_by(company: company, project: nil, provider: "insights")
      claimed = @client.claim(code: code, company_id: company.id, company_name: company.name,
                              deployment_id: Settings.insights.deployment_id,
                              deployment_secret: Settings.insights.deployment_secret)
      if existing && existing.credentials_data["organization_id"] != claimed[:organization_id]
        @client.disconnect(claimed[:secret])
        raise Error, "#{company.name} is already connected to #{existing.credentials_data['organization_name']}. " \
                     "Disconnect it before connecting another organization."
      end

      integration = existing || Integration.new(company: company, project: nil, provider: "insights")
      integration.assign_attributes(name: "Aixle Insights — #{claimed[:organization_name]}", status: "active",
                                    connected_by: user)
      integration.credentials_data = credentials(claimed)
      integration.save!
      integration
    rescue Client::Error => e
      raise Error, claim_message(e)
    end

    def rotate!(integration)
      secret = @client.rotate(secret_of(integration))
      integration.credentials_data = integration.credentials_data.merge("secret" => secret)
      integration.update!(status: "active")
    rescue Client::Error => e
      mark_rejected(integration) if e.unauthorized?
      raise Error, e.message
    end

    # Flow forgets the secret only after Insights has revoked it, so a failed call never
    # leaves a live secret that nobody tracks.
    def disconnect!(integration)
      @client.disconnect(secret_of(integration))
      InsightsSessionExport.where(integration: integration, state: "pending").update_all(state: "skipped")
      integration.destroy!
    rescue Client::Error => e
      raise Error, "Insights could not be reached to revoke the connection (#{e.message}); try again"
    end

    def projects(integration)
      @client.projects(secret_of(integration))
    rescue Client::Error => e
      mark_rejected(integration) if e.unauthorized?
      raise Error, e.message
    end

    def mark_rejected(integration)
      integration.update!(status: "error")
    end

    def secret_of(integration)
      integration.credentials_data.fetch("secret")
    end

    private

    def credentials(claimed)
      { "connection_id" => claimed[:connection_id], "secret" => claimed[:secret],
        "organization_id" => claimed[:organization_id], "organization_name" => claimed[:organization_name] }
    end

    def claim_message(error)
      case error.status
      when 422 then "That code is not valid — it may have expired or been used. Ask an Insights owner for a new one."
      when 401, 403 then "Insights does not recognize this Flow deployment. Its operator must register it with Insights."
      when 429 then "Too many attempts. Try again in a minute."
      else "Insights could not be reached (#{error.message}). Try again."
      end
    end
  end
end
