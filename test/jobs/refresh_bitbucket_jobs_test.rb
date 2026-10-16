# frozen_string_literal: true

require "test_helper"

class RefreshBitbucketJobsTest < ActiveJob::TestCase
  setup { with_bitbucket_settings(app_mode: true) }

  def json(body) = { status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json }

  test "a newly seen installation learns its workspace's name" do
    installation = create(:bitbucket_installation, :with_token, workspace_slug: nil, workspace_name: nil)
    stub_request(:get, "#{BITBUCKET_API}/workspaces/#{ERB::Util.url_encode(installation.workspace_uuid)}")
      .to_return(json({ uuid: installation.workspace_uuid, slug: "acme", name: "Acme Inc" }))

    RefreshBitbucketInstallationJob.perform_now(installation.id)

    assert_equal %w[acme Acme\ Inc], installation.reload.then { |i| [ i.workspace_slug, i.workspace_name ] }
  end

  test "permissions that have not landed yet leave the name for the next heartbeat" do
    installation = create(:bitbucket_installation, :with_token, workspace_slug: nil)
    stub_request(:get, "#{BITBUCKET_API}/workspaces/#{ERB::Util.url_encode(installation.workspace_uuid)}").to_return(status: 403)

    RefreshBitbucketInstallationJob.perform_now(installation.id)

    assert_nil installation.reload.workspace_slug
  end

  test "a renamed repository keeps its row under its new name" do
    integration = create(:integration, :bitbucket_app, :active)
    installation = integration.bitbucket_installation
    repository = create(:repository, :bitbucket, integration: integration, full_name: "acme/old-name")
    stub_request(:get, "#{BITBUCKET_API}/repositories/#{ERB::Util.url_encode(installation.workspace_uuid)}/" \
                       "#{ERB::Util.url_encode(repository.external_id)}")
      .to_return(json({ uuid: repository.external_id, full_name: "acme/new-name" }))

    RefreshBitbucketRepositoryJob.perform_now(installation_id: installation.id, repository_uuid: repository.external_id)

    assert_equal [ "acme/new-name", "https://bitbucket.org/acme/new-name.git" ],
                 repository.reload.then { |r| [ r.full_name, r.clone_url ] }
  end

  test "a repository no row names costs no request" do
    installation = create(:bitbucket_installation, :with_token)

    RefreshBitbucketRepositoryJob.perform_now(installation_id: installation.id, repository_uuid: "{#{SecureRandom.uuid}}")

    assert_not_requested :any, /api\.bitbucket\.org/
  end
end
