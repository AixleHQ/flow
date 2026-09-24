# frozen_string_literal: true

require "test_helper"

class Templates::CatalogSyncTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")

  setup do
    @repo = FakeTemplatesRepository.new.add_template_dir(FIXTURE)
  end

  def sync = Templates::CatalogSync.new(client: @repo).call

  test "mirrors a valid template with its files, commit and digest" do
    result = sync

    assert_equal 1, result.upserted
    row = CatalogTemplate.find_by!(slug: "dev-team-sdlc")
    assert_equal @repo.head_sha, row.commit_sha
    assert_equal "project", row.kind
    assert_equal 3, row.version
    assert_predicate row, :installable
    assert_match(/Connect GitHub first/, row.setup_markdown)
    package = row.to_package
    assert_equal Templates::Package.from_directory(FIXTURE).digest, package.digest
    assert_equal package.digest, row.package_digest
  end

  test "a second run at the same commit downloads nothing" do
    sync

    result = sync

    assert result.unchanged
    assert_equal 1, @repo.tarball_requests.size
  end

  test "an invalid template is skipped with its reason, the rest still mirror" do
    @repo.add_template_dir(FIXTURE, slug: "broken")

    result = sync

    assert_equal [ "dev-team-sdlc" ], CatalogTemplate.pluck(:slug)
    assert_equal "broken", result.skipped.first[:slug]
    assert_match(/does not match slug/, result.skipped.first[:reason])
  end

  test "a template removed from the repository is revoked, not deleted" do
    sync
    @repo.remove_template("dev-team-sdlc").commit!

    sync

    row = CatalogTemplate.find_by!(slug: "dev-team-sdlc")
    assert_predicate row, :revoked?
    assert_equal Templates::CatalogSync::REMOVED_REASON, row.revocation_reason
    assert_empty CatalogTemplate.listed
  end

  test "revoked.yaml withdraws a template that is still in the repository" do
    @repo.put("revoked.yaml", "- { slug: dev-team-sdlc, reason: Ships a broken image. }")

    sync

    row = CatalogTemplate.find_by!(slug: "dev-team-sdlc")
    assert_equal "Ships a broken image.", row.revocation_reason
    assert_predicate row, :revoked?
  end
end
