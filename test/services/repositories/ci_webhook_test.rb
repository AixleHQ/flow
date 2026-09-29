# frozen_string_literal: true

require "test_helper"

module Repositories
  class CiWebhookTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def repository_on(provider)
      create(:repository, full_name: "group/app", scope: @project,
                          integration: create(:integration, provider, :active, company: @company, connected_by: @user))
    end

    test "a GitLab repository gets its hook when added and loses it when removed" do
      repository = repository_on(:gitlab)
      gitlab = mock("gitlab repository service")
      gitlab.expects(:configure).with(repository).returns("secret")
      gitlab.expects(:remove).with(repository)
      ::Gitlab::RepositoryService.stubs(:new).with(repository.integration).returns(gitlab)

      CiWebhook.register(repository)
      CiWebhook.unregister(repository)
    end

    test "a hook GitLab refuses does not stop the repository from being added" do
      repository = repository_on(:gitlab)
      gitlab = mock("gitlab repository service")
      gitlab.stubs(:configure).raises(StandardError, "403 Forbidden")
      ::Gitlab::RepositoryService.stubs(:new).returns(gitlab)

      assert_nil CiWebhook.register(repository)
    end

    test "nothing is registered for a GitHub repository" do
      ::Gitlab::RepositoryService.expects(:new).never

      CiWebhook.register(repository_on(:github))
    end
  end
end
