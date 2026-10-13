# frozen_string_literal: true

require "test_helper"

class ProjectMemorySourceVerifierTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @repository = create(:repository, :public_source, scope: @project)
    @revision = "a" * 40
    @source = { "repository_id" => @repository.id, "path" => "docs/spec.md", "revision" => @revision }
  end

  test "verifies the latest file commit on the configured branch" do
    stub_request(:get, "https://api.github.com/repos/#{@repository.full_name}/commits")
      .with(query: { sha: "main", path: "docs/spec.md", per_page: "1" })
      .to_return(status: 200, body: [ { sha: @revision } ].to_json)

    assert ProjectMemorySourceVerifier.build.current?(project: @project, sources: [ @source ])
  end

  test "refuses changed files unavailable sources and foreign repositories" do
    stub_request(:get, "https://api.github.com/repos/#{@repository.full_name}/commits")
      .with(query: { sha: "main", path: "docs/spec.md", per_page: "1" })
      .to_return(status: 200, body: [ { sha: "b" * 40 } ].to_json)
    verifier = ProjectMemorySourceVerifier.build
    assert_not verifier.current?(project: @project, sources: [ @source ])
    assert_not verifier.current?(project: create(:project, :standalone), sources: [ @source ])
    assert_not verifier.current?(project: @project, sources: [])
  end

  test "fails closed without following redirects or exposing response text" do
    stub_request(:get, "https://api.github.com/repos/#{@repository.full_name}/commits")
      .with(query: { sha: "main", path: "docs/spec.md", per_page: "1" })
      .to_return(status: 302, headers: { "Location" => "https://example.org/private" })

    assert_not ProjectMemorySourceVerifier.build.current?(project: @project, sources: [ @source ])
  end

  test "rejects malformed sources before making requests" do
    verifier = ProjectMemorySourceVerifier.build
    assert_not verifier.current?(project: @project, sources: [ @source.merge("path" => "../secrets") ])
    assert_not verifier.current?(project: @project, sources: [ @source.merge("revision" => "main") ])
    assert_not verifier.current?(project: @project, sources: [ @source ] * 4)
  end

  test "bounds the whole verification including delayed responses" do
    stub_request(:get, "https://api.github.com/repos/#{@repository.full_name}/commits")
      .with(query: { sha: "main", path: "docs/spec.md", per_page: "1" })
      .to_return do
        sleep 0.05
        { status: 200, body: [ { sha: @revision } ].to_json }
      end

    assert_not ProjectMemorySourceVerifier.new(timeout_seconds: 0.005).current?(project: @project, sources: [ @source ])
  end
end
