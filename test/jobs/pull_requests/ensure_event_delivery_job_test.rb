# frozen_string_literal: true

require "test_helper"

class PullRequests::EnsureEventDeliveryJobTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:protocol).returns("https")
    Settings.stubs(:domain).returns("flow.example.com")
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
  end

  def gitlab_repository
    create(:repository, full_name: "group/app", scope: @project,
                        integration: create(:integration, :gitlab, :active, company: @company, connected_by: @user))
  end

  def pr_binding(**attributes)
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                             event_type: "pull_request.comment.created", **attributes)
  end

  test "a GitLab repository's hook gains the events a pull-request trigger waits for" do
    repository = gitlab_repository
    gitlab = mock("gitlab repository service")
    gitlab.expects(:ensure_hook_events).with(repository)
    Gitlab::RepositoryService.stubs(:new).returns(gitlab)

    PullRequests::EnsureEventDeliveryJob.perform_now(pr_binding(repository: repository).id)
  end

  test "an Azure DevOps connection gains its pull-request comment Service Hook and the update hook votes arrive on" do
    with_azure_devops_enabled
    AzureDevops::AppConfig.stubs(:webhooks_enabled?).returns(true)
    integration = create(:integration, :azure_devops, :active)
    project = integration.project
    create(:repository, :azure_devops, integration: integration, scope: project)
    binding = create(:trigger_binding, project: project, workflow: create(:workflow, scope: project), created_by: project.owner,
                                       event_type: "pull_request.comment.created")
    hooks = mock("subscription service")
    hooks.expects(:ensure_all!).with(event_types: AzureDevopsSubscription::GATE_EVENT_TYPES +
                                                  AzureDevopsSubscription::PULL_REQUEST_EVENT_TYPES)
    AzureDevops::SubscriptionService.stubs(:new).with(integration).returns(hooks)

    PullRequests::EnsureEventDeliveryJob.perform_now(binding.id)
  end

  test "a disabled trigger asks no host for anything" do
    gitlab_repository
    Gitlab::RepositoryService.expects(:new).never

    PullRequests::EnsureEventDeliveryJob.perform_now(pr_binding(enabled: false).id)
  end
end
