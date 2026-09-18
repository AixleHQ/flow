# frozen_string_literal: true

module Integrations
  class DisconnectService
    def self.call(integration)
      Integration.transaction do
        # Keep accepted callback rows for audit while revoking new admission.
        integration.youtrack_webhook_endpoint&.update!(enabled: false) if integration.youtrack?
        integration.trigger_bindings.update_all(enabled: false)
        integration.destroy!
      end
    end
  end
end
