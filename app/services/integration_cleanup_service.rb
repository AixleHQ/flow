# frozen_string_literal: true

# IntegrationCleanupService — provider-agnostic teardown hook invoked when a
# terminal session ends. Each integration that needs runtime
# state released (workspace locks, leases, ephemeral credentials, …) is
# dispatched from here so session strategies stay integration-free.
#
# Add a new integration's teardown by extending `PROVIDER_HOOKS` with another
# entry pointing at the provider's release class method.
class IntegrationCleanupService
  PROVIDER_HOOKS = [
    ->(session) { Coder::LockService.release_all_for_session(session) }
  ].freeze

  def self.release_session_locks!(session)
    return unless session

    PROVIDER_HOOKS.each do |hook|
      hook.call(session)
    rescue StandardError => e
      Rails.logger.warn("[IntegrationCleanupService] hook failed: #{e.message}")
    end
  end
end
