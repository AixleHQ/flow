# frozen_string_literal: true

module PullRequests
  # A pull-request trigger was created or enabled: make sure the hosts deliver
  # the events it waits for. A GitLab repository's hook gains merge-request and
  # note events; an Azure DevOps connection gains its comment Service Hook.
  # GitHub and Bitbucket deliver through their apps, with nothing to set up per
  # repository. Out of the request, because it calls the hosts.
  #
  # An Azure connection's gate hooks are ensured too: a vote arrives on
  # `git.pullrequest.updated`, and a connection set up before Service Hooks were
  # reachable has none.
  class EnsureEventDeliveryJob < ApplicationJob
    queue_as :default

    def perform(trigger_binding_id)
      binding = TriggerBinding.find_by(id: trigger_binding_id)
      return unless binding&.enabled? && binding.pull_request_event?

      repositories = binding.repository ? [ binding.repository ] : Repository.where(scope: binding.project).includes(:integration).to_a
      repositories.each { |repository| Repositories::CiWebhook.ensure_pull_request_events(repository) }
      azure_integrations(repositories).each { |integration| ensure_azure_hooks(integration) }
    end

    private

    def azure_integrations(repositories)
      repositories.filter_map(&:integration).select { |integration| integration.provider.to_s == "azure_devops" }
                  .select(&:active?).uniq
    end

    def ensure_azure_hooks(integration)
      return unless ::AzureDevops::AppConfig.webhooks_enabled?

      ::AzureDevops::SubscriptionService.new(integration)
                                        .ensure_all!(event_types: AzureDevopsSubscription::GATE_EVENT_TYPES +
                                                     AzureDevopsSubscription::PULL_REQUEST_EVENT_TYPES)
    rescue ::AzureDevops::Error => e
      Rails.logger.warn("[PullRequests::EnsureEventDeliveryJob] integration #{integration.id}: #{e.message}")
    end
  end
end
