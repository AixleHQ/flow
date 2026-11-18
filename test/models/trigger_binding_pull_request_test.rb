# frozen_string_literal: true

require "test_helper"

class TriggerBindingPullRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @repository = create(:repository, scope: @project, full_name: "acme/api",
                                      integration: create(:integration, :github, :active, company: @company, project: @project))
    @workflow = create(:workflow, scope: @project)
  end

  def binding(**attributes)
    build(:trigger_binding, **{ project: @project, workflow: @workflow, created_by: @user,
                                event_type: "pull_request.review.submitted" }.merge(attributes))
  end

  test "a pull-request trigger takes one of the two pull-request event types" do
    assert binding.valid?
    assert binding(event_type: "pull_request.comment.created").valid?

    unknown = binding(event_type: "pull_request.opened")
    assert_not unknown.valid?
    assert_includes unknown.errors[:event_type].join, "pull_request.review.submitted"
  end

  test "it may name only a repository of its own project that a code host delivers events for" do
    assert binding(repository: @repository).valid?

    public_one = create(:repository, :public_source, scope: @project, full_name: "rails/rails")
    other_project = create(:project, company: @company, owner: @user)
    elsewhere = create(:repository, scope: other_project, full_name: "acme/web",
                                    integration: create(:integration, :github, :active, company: @company, project: other_project))
    [ public_one, elsewhere ].each do |repository|
      candidate = binding(repository: repository)
      assert_not candidate.valid?
      assert_includes candidate.errors[:repository].join, "must be a repository of this project"
    end
  end

  test "only a pull-request trigger names a repository" do
    webhook_one = binding(event_type: "webhook.received", repository: @repository)

    assert_not webhook_one.valid?
    assert_includes webhook_one.errors[:repository_id], "is only for pull-request triggers"
  end

  test "a trigger bound to a repository matches only that repository's events" do
    scoped = binding(repository: @repository)

    assert scoped.matches?({ "repository" => { "id" => @repository.id } })
    assert_not scoped.matches?({ "repository" => { "id" => @repository.id + 1 } })
    assert binding.matches?({ "repository" => { "id" => @repository.id + 1 } }), "no repository means any"
  end

  test "a generic webhook cannot pass itself off as a pull-request event" do
    binding.save!
    forged = TriggerEvent.create!(event_type: "pull_request.review.submitted", source: "github:wh-1", project: @project,
                                  data: { "review" => { "verdict" => "changes_requested" } })
    real = TriggerEvent.create!(event_type: "pull_request.review.submitted", source: "pull_request", project: @project,
                                data: { "review" => { "verdict" => "changes_requested" } })

    assert_empty TriggerBinding.for_event(forged)
    assert_equal 1, TriggerBinding.for_event(real).count
  end

  test "enabling a pull-request trigger makes the hosts deliver its events" do
    assert_enqueued_with(job: PullRequests::EnsureEventDeliveryJob) { binding.save! }
  end

  test "removing the repository removes the triggers bound to it, rather than widening them" do
    bound = binding(repository: @repository).tap(&:save!)
    any = binding.tap(&:save!)

    @repository.destroy!

    assert_not TriggerBinding.exists?(bound.id)
    assert TriggerBinding.exists?(any.id)
  end
end
