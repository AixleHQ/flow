# frozen_string_literal: true

module Github
  # GitHub's `installation` webhook, applied to every connection that runs on
  # the installation — in any company, since one installation can serve several
  # (Github::InstallationOwnership). GitHub sends it to every App without a
  # subscription.
  class InstallationEvents
    UNINSTALLED = "The GitHub App was uninstalled on GitHub. Install it again, or remove this connection."
    SUSPENDED = "The GitHub App installation is suspended on GitHub. Unsuspend it there to use this connection."

    def self.apply(action:, installation_id:, permissions: nil)
      new(installation_id).apply(action, permissions: permissions)
    end

    def initialize(installation_id)
      @installation_id = installation_id
    end

    def apply(action, permissions: nil)
      case action
      when "deleted" then take_down("uninstalled", UNINSTALLED)
      when "suspend" then take_down("suspended", SUSPENDED)
      when "unsuspend" then bring_back_suspended
      when "new_permissions_accepted" then record_permissions(permissions)
      end
    end

    private

    def connections
      Integration.where(provider: :github, github_installation_id: @installation_id)
    end

    def take_down(state, message)
      connections.find_each do |integration|
        integration.update_columns(
          status: "error", updated_at: Time.current,
          settings: integration.settings.to_h.merge("installation_state" => state, "error" => message)
        )
      end
    end

    # An organization owner approved what the App asked for since it was
    # installed, such as the Projects permission GitHub trackers need.
    def record_permissions(permissions)
      return unless permissions.is_a?(Hash)

      connections.find_each do |integration|
        integration.update_columns(settings: integration.settings.to_h.merge("app_permissions" => permissions.to_h),
                                   updated_at: Time.current)
      end
    end

    # Only what the suspension took down comes back; a connection in error for
    # another reason stays in error until it is tested.
    def bring_back_suspended
      connections.find_each do |integration|
        next unless integration.settings.to_h["installation_state"] == "suspended"

        integration.status = :active
        integration.settings = integration.settings.to_h.except("installation_state", "error")
        next if integration.save

        Rails.logger.warn("[Github::InstallationEvents] integration #{integration.id} stays in error after unsuspend: " \
                          "#{integration.errors.full_messages.to_sentence}")
      end
    end
  end
end
