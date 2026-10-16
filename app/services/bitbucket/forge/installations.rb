# frozen_string_literal: true

module Bitbucket
  module Forge
    # What a verified invocation says about its installation: that it exists
    # (created on first sight, unbound), the token it pushed, and its removal.
    module Installations
      REMOVED = "The Aixle Flow app was removed from this Bitbucket workspace. Install it again, or remove this connection."
      DISCONNECTED = "A Bitbucket workspace administrator disconnected this workspace from Aixle. Connect it again from " \
                     "Workspace settings → Aixle Flow."

      module_function

      # The installation, with the pushed token stored by the expiry rule — or
      # nil for one already uninstalled: a delivery that arrives late must not
      # bring a removed installation back.
      def record!(invocation, system_token:, installer_account_id: nil)
        installation = BitbucketInstallation.find_by(forge_installation_id: invocation.installation_id) ||
                       create_for(invocation, installer_account_id)
        return if installation.uninstalled?

        installation.store_token!(system_token, expires_at: SystemToken.expires_at(system_token))
        if invocation.app_version && installation.app_version != invocation.app_version
          installation.update_columns(app_version: invocation.app_version, updated_at: Time.current)
        end
        RefreshBitbucketInstallationJob.perform_later(installation.id) if installation.workspace_slug.blank?
        installation
      end

      def uninstall!(installation)
        installation.update!(status: :uninstalled, encrypted_access_token: nil, token_expires_at: nil)
        take_down(installation, "uninstalled", REMOVED)
      end

      # The workspace stops being this company's; the installation stays, ready
      # to be connected again.
      def unbind!(installation)
        installation.update!(company: nil, bound_by: nil, bound_at: nil)
        take_down(installation, "disconnected", DISCONNECTED)
      end

      # A reinstall arrives under a new installation id while the old row may
      # still look live — preUninstall is best effort — and only one live row per
      # workspace may exist.
      def create_for(invocation, installer_account_id)
        BitbucketInstallation.transaction do
          BitbucketInstallation.live
                               .where(forge_environment_id: invocation.environment_id, workspace_uuid: invocation.workspace_uuid)
                               .where.not(forge_installation_id: invocation.installation_id)
                               .find_each { |previous| uninstall!(previous) }
          BitbucketInstallation.create!(forge_installation_id: invocation.installation_id,
                                        forge_environment_id: invocation.environment_id,
                                        workspace_uuid: invocation.workspace_uuid,
                                        installer_account_id: installer_account_id.presence,
                                        app_version: invocation.app_version)
        end
      rescue ActiveRecord::RecordNotUnique
        BitbucketInstallation.find_by!(forge_installation_id: invocation.installation_id)
      end

      def take_down(installation, state, message)
        installation.integrations.find_each do |integration|
          integration.update_columns(
            status: "error", updated_at: Time.current,
            settings: integration.settings.to_h.merge("installation_state" => state, "error" => message)
          )
        end
      end
    end
  end
end
