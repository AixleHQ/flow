# frozen_string_literal: true

module Bitbucket
  module Forge
    # A project's app-mode connection to an installation its company has bound.
    module Connection
      RESTORABLE_STATES = %w[uninstalled disconnected].freeze

      module_function

      # Proves the app reaches the workspace's repositories, then creates or
      # reuses the project's connection. Nothing is saved when the proof fails.
      def connect!(installation:, project:, user:)
        unless installation.status.active? && installation.company_id == project.company_id
          raise Error::CredentialUnavailable, "This Bitbucket workspace is not connected to #{project.company.name}."
        end

        AppClient.for(installation).get("repositories", installation.workspace_uuid, params: { pagelen: 1 })

        integration = project.company.integrations.find_or_initialize_by(project: project, provider: "bitbucket",
                                                                        bitbucket_installation: installation)
        integration.credentials_data = {} if integration.new_record?
        integration.assign_attributes(
          name: installation.workspace_name.presence || installation.workspace_slug.presence || "Bitbucket",
          status: :active, connected_by: integration.connected_by || user,
          settings: integration.settings.to_h.except("error", "installation_state").merge(
            "auth_mode" => "app", "workspace_uuid" => installation.workspace_uuid,
            "workspace_slug" => installation.workspace_slug
          ).compact
        )
        integration.save!
        integration
      end

      # After a reinstall the company's connections still point at the removed
      # installation, and after a disconnect they sit in error. Binding the
      # workspace again brings them back, repositories and all.
      def restore!(installation)
        previous = BitbucketInstallation.with_status(:uninstalled)
                                        .where(company_id: installation.company_id, workspace_uuid: installation.workspace_uuid,
                                               forge_environment_id: installation.forge_environment_id)
                                        .where.not(id: installation.id)
        Integration.where(company_id: installation.company_id)
                   .where(bitbucket_installation_id: [ installation.id, *previous.ids ])
                   .find_each do |integration|
          next unless RESTORABLE_STATES.include?(integration.settings.to_h["installation_state"])

          integration.update!(bitbucket_installation: installation, status: :active,
                              settings: integration.settings.to_h.except("error", "installation_state"))
        end
      end
    end
  end
end
