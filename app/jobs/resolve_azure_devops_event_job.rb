# frozen_string_literal: true

# Turns one Service Hook delivery into a gate resolution, by going back to Azure
# rather than by believing the payload.
#
# The payload is a notification. `git.pullrequest.merged` in particular reports a
# merge ATTEMPT — it fires for a merge that failed on a conflict just as it does
# for one that landed — so resolving a gate from its contents would mark CI green
# for a merge that never happened.
class ResolveAzureDevopsEventJob < ApplicationJob
  queue_as :default

  def perform(subscription_id:, event_type:, resource: {})
    subscription = AzureDevopsSubscription.find_by(id: subscription_id)
    return if subscription.nil?

    integration = subscription.integration
    return unless integration&.active?

    case event_type
    when "build.complete" then resolve_build(integration, resource)
    when "git.pullrequest.merged", "git.pullrequest.updated" then resolve_pull_request(integration, resource)
    end
  rescue AzureDevops::Error => e
    # A transient Azure failure leaves the gate pending, which the reconciliation
    # sweep picks up later. Raising here would only retry the whole job against a
    # provider that is already unhappy.
    Rails.logger.warn("[ResolveAzureDevopsEventJob] subscription #{subscription_id} #{event_type}: #{e.code}")
  end

  private

  def resolve_build(integration, resource)
    build_id = resource["id"]
    repository_id = resource.dig("repository", "id")
    return if build_id.blank?

    build = AzureDevops::BuildService.new(integration).get(build_id)
    # `status` is the lifecycle and `result` is the verdict; a build that is not
    # completed has no verdict to report, whatever the event claimed.
    return unless build[:status].to_s == "completed"

    GateService.resolve_azure_devops_build(
      external_repository_id: repository_id.presence || build[:repository_id],
      build_id: build_id,
      result: build[:result],
      commit: build[:commit]
    )
  end

  def resolve_pull_request(integration, resource)
    pull_request_id = resource["pullRequestId"]
    repository_id = resource.dig("repository", "id")
    return if pull_request_id.blank? || repository_id.blank?

    repository = Repository.find_by(external_id: repository_id, integration_id: integration.id)
    return if repository.nil?

    policies = AzureDevops::BuildService.new(integration).policy_evaluations(repository, pull_request_id)
    return if policies[:blocking_count].to_i.zero?

    pull_request = AzureDevops::PullRequestService.new(integration).get(repository, pull_request_id)

    GateService.resolve_azure_devops_pr_policies(
      external_repository_id: repository_id,
      pull_request_id: pull_request_id,
      satisfied: policies[:all_blocking_satisfied],
      commit: pull_request[:last_merge_source_commit],
      unsatisfied: policies[:unsatisfied]
    )
  end
end
