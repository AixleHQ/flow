# frozen_string_literal: true

require "test_helper"

class Templates::CatalogSyncTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")

  setup do
    @repo = FakeTemplatesRepository.new.add_template_dir(FIXTURE)
  end

  def sync = Templates::CatalogSync.new(client: @repo).call

  test "mirrors the publishers and a valid template with its files, commit and digest" do
    result = sync

    assert_equal 1, result.upserted
    publisher = CatalogNamespace.find_by!(name: "acme")
    assert_equal [ "Acme Corp", true, [ "acme-bot" ] ], [ publisher.display_name, publisher.verified, publisher.owners ]
    row = CatalogTemplate.find_by_identifier("acme/dev-team-sdlc")
    assert_equal @repo.head_sha, row.commit_sha
    assert_equal "project", row.kind
    assert_match(/Connect GitHub first/, row.setup_markdown)
    assert_equal Templates::Package.from_directory(FIXTURE).digest, row.package_digest
  end

  test "a second run at the same commit downloads nothing" do
    sync

    assert sync.unchanged
    assert_equal 1, @repo.tarball_requests.size
  end

  test "two publishers can each have a template with the same slug" do
    other = Dir.mktmpdir
    FileUtils.cp_r("#{FIXTURE}/.", other)
    File.write("#{other}/template.yaml", File.read("#{other}/template.yaml").sub("namespace: acme", "namespace: globex"))
    @repo.add_template_dir(other, namespace: "globex", slug: "dev-team-sdlc")
    @repo.put("namespaces.yaml", "#{FakeTemplatesRepository::DEFAULT_NAMESPACES}- { name: globex, owners: [globex-dev] }\n")

    sync

    assert_equal %w[acme/dev-team-sdlc globex/dev-team-sdlc], CatalogTemplate.all.map(&:identifier).sort
  ensure
    FileUtils.rm_rf(other)
  end

  test "a template under an unregistered namespace is skipped" do
    @repo.put("namespaces.yaml", "[]")

    result = sync

    assert_empty CatalogTemplate.all
    assert_equal "acme/dev-team-sdlc", result.skipped.first[:identifier]
    assert_match(/not registered/, result.skipped.first[:reason])
  end

  test "a template whose directory does not match its namespace/slug is skipped" do
    @repo.add_template_dir(FIXTURE, slug: "renamed")

    result = sync

    assert_equal [ "acme/dev-team-sdlc" ], CatalogTemplate.all.map(&:identifier)
    assert_match(/does not match namespace\/slug/, result.skipped.find { |s| s[:identifier] == "acme/renamed" }[:reason])
  end

  test "a template removed from the repository is revoked, not deleted" do
    sync
    @repo.remove_template("acme/dev-team-sdlc").commit!

    sync

    row = CatalogTemplate.find_by_identifier("acme/dev-team-sdlc")
    assert_predicate row, :revoked?
    assert_equal Templates::CatalogSync::REMOVED_REASON, row.revocation_reason
  end

  test "revoked.yaml withdraws a template that is still in the repository" do
    @repo.put("revoked.yaml", "- { template: acme/dev-team-sdlc, reason: Ships a broken image. }")

    sync

    assert_equal "Ships a broken image.", CatalogTemplate.find_by_identifier("acme/dev-team-sdlc").revocation_reason
  end
end
