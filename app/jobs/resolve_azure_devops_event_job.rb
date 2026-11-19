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
  retry_on Trackers::EventPipeline::WriteInFlight, wait: Trackers::EventPipeline::WRITE_RETRY_WAIT,
                                                   attempts: Trackers::EventPipeline::WRITE_RETRY_ATTEMPTS

  def perform(subscription_id:, event_type:, resource: {}, occurred_at: nil)
    subscription = AzureDevopsSubscription.find_by(id: subscription_id)
    return if subscription.nil?

    integration = subscription.integration
    return unless integration&.active?

    case event_type
    when "build.complete" then resolve_build(integration, resource)
    when "git.pullrequest.merged" then resolve_pull_request(integration, resource)
    when "git.pullrequest.updated"
      publish_pull_request_votes(integration, resource, occurred_at)
      resolve_pull_request(integration, resource)
    when *AzureDevopsSubscription::TRACKER_EVENT_TYPES then publish_tracker_event(subscription, event_type, resource)
    when *AzureDevopsSubscription::PULL_REQUEST_EVENT_TYPES then publish_pull_request_event(integration, event_type, resource)
    end
  rescue AzureDevops::Error, Trackers::Error => e
    # A transient Azure failure leaves the gate pending, which the reconciliation
    # sweep picks up later. Raising here would only retry the whole job against a
    # provider that is already unhappy.
    Rails.logger.warn("[ResolveAzureDevopsEventJob] subscription #{subscription_id} #{event_type}: #{e.code}")
  end

  private

  def publish_tracker_event(subscription, event_type, resource)
    notification = Trackers::AzureDevops::Notifications.parse(event_type, resource, scope_id: subscription.azure_project_id)
    return unless notification

    retries_left = executions < Trackers::EventPipeline::WRITE_RETRY_ATTEMPTS
    Trackers::EventPipeline.new(subscription.integration, wait_for_writes: retries_left).process(notification)
  end

  # The repository has to be one this connection owns, as for a gate.
  def publish_pull_request_event(integration, event_type, resource)
    event = PullRequests::AzureDevops::Events.parse(event_type, resource)
    external_id = PullRequests::AzureDevops::Events.repository_id(resource)
    return if event.nil? || external_id.nil?

    repositories = Repository.where(integration_id: integration.id, external_id: external_id).preload(:integration, :scope)
    PullRequests::EventPipeline.process(event, repositories.to_a)
  end

  # Only while a review trigger waits on the repository: answering every update
  # costs a read of the pull request's threads. A failed read loses the vote but
  # not the gate resolution after it.
  def publish_pull_request_votes(integration, resource, occurred_at)
    number = resource["pullRequestId"]
    external_id = resource.dig("repository", "id")
    return if number.blank? || external_id.blank?

    repositories = PullRequests::EventPipeline.awaited(
      Repository.where(integration_id: integration.id, external_id: external_id).preload(:integration, :scope).to_a,
      event_types: [ PullRequests::EventPipeline::REVIEW_SUBMITTED ]
    )
    return if repositories.empty?

    updates = AzureDevops::PullRequestService.new(integration).vote_updates(repositories.first, number)
    PullRequests::AzureDevops::Events.votes(resource, updates, at: occurred_at).each do |event|
      PullRequests::EventPipeline.process(event, repositories)
    end
  rescue AzureDevops::Error => e
    Rails.logger.warn("[ResolveAzureDevopsEventJob] votes of pull request #{number}: #{e.code}")
  end

  def resolve_build(integration, resource)
    build_id = resource["id"]
    return if build_id.blank?

    build = AzureDevops::BuildService.new(integration).get(build_id)
    # `status` is the lifecycle and `result` is the verdict; a build that is not
    # completed has no verdict to report, whatever the event claimed.
    return unless build[:status].to_s == "completed"

    # The repository comes from AZURE's answer, not from the payload, and it has
    # to be one this connection actually owns. Routing on the delivered id would
    # let a delivery on one project's subscription resolve gates in another
    # project that happens to hold that repository — the gate scope looks
    # repositories up across every project.
    repository = owned_repository(integration, build[:repository_id])
    return if repository.nil?

    GateService.resolve_azure_devops_build(
      external_repository_id: repository.external_id,
      build_id: build_id,
      result: build[:result],
      commit: build[:commit]
    )
  end

  def owned_repository(integration, external_id)
    return nil if external_id.blank?

    Repository.find_by(external_id: external_id, integration_id: integration.id)
  end

  def resolve_pull_request(integration, resource)
    pull_request_id = resource["pullRequestId"]
    repository_id = resource.dig("repository", "id")
    return if pull_request_id.blank? || repository_id.blank?

    repository = owned_repository(integration, repository_id)
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
