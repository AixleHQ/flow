# frozen_string_literal: true

require "test_helper"

class PullRequests::ProcessBitbucketEventJobTest < ActiveSupport::TestCase
  ADA = "{7a1b2c3d-0000-4000-8000-0000000000ad}"

  setup do
    with_bitbucket_settings(app_mode: true)
    @fake = stub_bitbucket!
    @integration = create(:integration, :bitbucket_app, :active)
    @project = @integration.project
    @repository = create(:repository, :bitbucket, integration: @integration, scope: @project, full_name: "acme/api",
                                                  external_id: FakeBitbucket::Api::REPOSITORY_UUID,
                                                  external_organization_id: FakeBitbucket::Api::WORKSPACE_UUID)
    @workflow = create(:workflow, scope: @project)
  end

  def payload(event_type, **extra)
    { "eventType" => event_type, "selfGenerated" => false, "actor" => { "uuid" => ADA },
      "repository" => { "uuid" => FakeBitbucket::Api::REPOSITORY_UUID },
      "pullrequest" => { "id" => 7, "title" => { "value" => "Add billing" }, "source" => { "branch" => "feature" } } }.merge(extra)
  end

  def perform(payload)
    PullRequests::ProcessBitbucketEventJob.perform_now(installation_id: @integration.bitbucket_installation_id, payload: payload)
  end

  test "a comment event reads the comment it names and publishes its text and place in the diff" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @project.owner,
                             event_type: "pull_request.comment.created")
    comment = @fake.add_comment(FakeBitbucket::Api::REPOSITORY_UUID, 7, author: "Ada", author_uuid: ADA,
                                                                        body: "Rename this", path: "app/billing.rb", line: 12)
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))

    perform(payload(PullRequests::Bitbucket::Events::COMMENT_CREATED, "comment" => { "id" => comment[:id] }))

    event = TriggerEvent.sole
    assert_equal [ "Rename this", "app/billing.rb", 12 ], event.data["comment"].values_at("text", "file", "line")
    assert_equal({ "id" => ADA, "name" => "Ada", "is_me" => false }, event.data["actor"])
  end

  test "nothing is read from Bitbucket while no pull-request trigger waits on the repository" do
    perform(payload(PullRequests::Bitbucket::Events::COMMENT_CREATED, "comment" => { "id" => 1 }))

    assert_not @fake.called?(:comment)
    assert_equal 0, TriggerEvent.count
  end

  test "a review the app itself made is Aixle's, and ignored by default" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @project.owner,
                             event_type: "pull_request.review.submitted")
    WorkflowService.expects(:enqueue).never

    perform(payload(PullRequests::Bitbucket::Events::REVIEWER_STATUS, "selfGenerated" => true,
                    "reviewers" => { "value" => [ { "user" => { "uuid" => ADA }, "status" => "approved" } ] }))

    assert_equal true, TriggerEvent.sole.data.dig("origin", "aixle") # rubocop:disable Minitest/AssertTruthy
  end
end
