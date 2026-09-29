# frozen_string_literal: true

require "test_helper"

module Activities
  module Templates
    class SyncCatalogActivityTest < ActiveSupport::TestCase
      test "mirrors the repository and reports what it did" do
        repo = FakeTemplatesRepository.new.add_template_dir(Rails.root.join("test/fixtures/files/templates/dev-team-sdlc"))
        ::Templates::RepositoryClient.stubs(:new).returns(repo)

        result = run_activity(SyncCatalogActivity)

        assert_equal repo.head_sha, result[:commit_sha]
        assert_equal 1, result[:upserted]
        assert_equal [], result[:skipped]
        assert CatalogTemplate.exists?(slug: "dev-team-sdlc")
      end
    end
  end
end
