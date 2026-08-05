# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class CreateRepositoryTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company, :admin)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
    end

    def execute(params)
      CreateRepository.new(params: { "project_id" => @project.id }.merge(params), user: @user).execute
    end

    test "attaches a repository through an integration" do
      result = nil
      assert_difference("Repository.count", 1) do
        result = execute("full_name" => "acme/app", "integration_id" => @integration.id, "source_branch" => "main")
      end

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      repo = Repository.find(payload["id"])

      assert_equal "acme/app", repo.full_name
      assert_equal "https://github.com/acme/app.git", repo.clone_url
      assert_equal false, payload["public_source"] # rubocop:disable Minitest/RefuteFalse
    end

    # The agent-side half of the public-repository path: an agent can attach the
    # OSS repository it was asked to read without anybody installing an App on it.
    test "attaches a verified public repository when given a url" do
      fake = FakePublicRepositoryService.new
      PublicRepositoryService.stubs(:new).returns(fake)

      result = nil
      assert_difference("Repository.count", 1) do
        result = execute("public_url" => "https://github.com/rails/rails", "purpose" => "Reference")
      end

      payload = JSON.parse(result[:stdout])
      repo = Repository.find(payload["id"])

      assert repo.public_source?
      assert_equal "rails/rails", repo.full_name
      assert_equal "https://github.com/rails/rails.git", repo.clone_url
      assert_equal "Reference", repo.purpose
      assert payload["public_source"]
    end

    test "reports why a public url could not be resolved" do
      error = PublicRepositoryService::NotPublic.new("acme/app is a private repository")
      PublicRepositoryService.stubs(:new).returns(FakePublicRepositoryService.new(error: error))

      assert_no_difference("Repository.count") do
        result = execute("public_url" => "https://github.com/acme/app")

        assert_not_equal 0, result[:exit_code]
        assert_match(/private repository/, result[:stderr])
      end
    end

    test "refuses a repository attached to an integration that does not host code" do
      linear = create(:integration, :linear, company: @company, connected_by: @user)

      assert_no_difference("Repository.count") do
        result = execute("full_name" => "acme/app", "integration_id" => linear.id)

        assert_not_equal 0, result[:exit_code]
        assert_match(/GitHub or GitLab/, result[:stderr])
      end
    end
  end
end
