# frozen_string_literal: true

require "test_helper"

module Bitbucket
  class RepositoryServiceTest < ActiveSupport::TestCase
    setup do
      with_bitbucket_settings
      @bitbucket = stub_bitbucket!
      @integration = create(:integration, :bitbucket, :active)
      @service = RepositoryService.new(@integration)
    end

    test "lists the connection's workspace with the identity a Repository row needs" do
      assert_equal [ {
        full_name: "acme/api", default_branch: "main", clone_url: "https://bitbucket.org/acme/api.git",
        is_private: true, description: "The api service", external_id: FakeBitbucket::Api::REPOSITORY_UUID,
        external_organization_id: FakeBitbucket::Api::WORKSPACE_UUID, external_project_id: FakeBitbucket::Api::PROJECT_UUID
      } ], @service.list_available
      assert_equal FakeBitbucket::Api::WORKSPACE_UUID, @bitbucket.calls_to(:repositories).first[:workspace]
    end

    test "a repository the credential reaches in another workspace is not this connection's" do
      @bitbucket.workspaces["other"] = { uuid: "{00000000-0000-4000-8000-0000000000ff}", slug: "other", name: "Other" }
      @bitbucket.add_repository(full_name: "other/secret", workspace_uuid: "{00000000-0000-4000-8000-0000000000ff}")

      assert_nil @service.find_repo("other/secret")
      assert_raises(Error::NotFound) { @service.find_repo!("other/secret") }
    end

    test "finds a repository by name or by UUID" do
      assert_equal "acme/api", @service.find_repo("acme/api")[:full_name]
      assert_equal "acme/api", @service.find_repo(FakeBitbucket::Api::REPOSITORY_UUID)[:full_name]
    end

    test "lists the branches of an attached repository by its UUIDs, not its name" do
      repository = create(:repository, :bitbucket, integration: @integration, full_name: "acme/renamed",
                                                   external_id: FakeBitbucket::Api::REPOSITORY_UUID)

      assert_equal %w[main feature], @service.list_branches(repository)
      assert_equal FakeBitbucket::Api::REPOSITORY_UUID, @bitbucket.calls_to(:branches).last[:repository]
    end

    test "a failed listing is an empty picker, not an error page" do
      @bitbucket.fail_on(:repositories, Error.new("down", code: "timeout"))

      assert_empty @service.list_available
    end
  end
end
