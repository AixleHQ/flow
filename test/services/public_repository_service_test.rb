# frozen_string_literal: true

require "test_helper"

# Contract tests (testing doctrine R4): the adapter is pinned to the real
# api.github.com / gitlab.com surfaces with WebMock stub_request + realistic
# payloads. Nothing here is authenticated — that is the point of the adapter.
class PublicRepositoryServiceTest < ActiveSupport::TestCase
  setup do
    Settings.github.stubs(:read_token).returns(nil)
  end

  # ====== GitHub ======

  test "resolves a public github repository from its url" do
    stub_github("rails/rails", default_branch: "main", description: "Ruby on Rails")

    result = PublicRepositoryService.resolve("https://github.com/rails/rails")

    assert_equal "github", result.provider
    assert_equal "rails/rails", result.full_name
    assert_equal "main", result.default_branch
    assert_equal "https://github.com/rails/rails.git", result.clone_url
    assert_equal "Ruby on Rails", result.description
  end

  test "builds the clone url from the canonical full_name, not from the input" do
    stub_request(:get, "https://api.github.com/repos/RAILS/Rails")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { full_name: "rails/rails", private: false, default_branch: "main",
                         clone_url: "https://github.com/attacker/evil.git" }.to_json)

    result = PublicRepositoryService.resolve("https://github.com/RAILS/Rails")

    assert_equal "rails/rails", result.full_name
    assert_equal "https://github.com/rails/rails.git", result.clone_url
  end

  test "accepts urls with a trailing .git, a host without a scheme, and a bare owner/repo" do
    stub_github("rails/rails")

    %w[https://github.com/rails/rails.git github.com/rails/rails rails/rails].each do |input|
      assert_equal "rails/rails", PublicRepositoryService.resolve(input).full_name, input
    end
  end

  test "resolves a deep link to the repository it points into" do
    stub_github("rails/rails")

    result = PublicRepositoryService.resolve("https://github.com/rails/rails/blob/main/Gemfile")

    assert_equal "rails/rails", result.full_name
  end

  test "sends the optional read token when one is configured" do
    Settings.github.stubs(:read_token).returns("ghp_read_only")
    request = stub_github("rails/rails").with(headers: { "Authorization" => "Bearer ghp_read_only" })

    PublicRepositoryService.resolve("https://github.com/rails/rails")

    assert_requested(request)
  end

  test "raises NotFound when github answers 404" do
    stub_request(:get, "https://api.github.com/repos/acme/secret")
      .to_return(status: 404, headers: { "Content-Type" => "application/json" },
                 body: { message: "Not Found" }.to_json)

    error = assert_raises(PublicRepositoryService::NotFound) do
      PublicRepositoryService.resolve("https://github.com/acme/secret")
    end
    assert_match(/not public/, error.message)
  end

  test "raises NotPublic when the repository is visible but private" do
    stub_github("acme/app", private: true)

    error = assert_raises(PublicRepositoryService::NotPublic) do
      PublicRepositoryService.resolve("https://github.com/acme/app")
    end
    assert_match(/private repository/, error.message)
  end

  test "raises TransportError when the rate limit is exhausted" do
    stub_request(:get, "https://api.github.com/repos/rails/rails")
      .to_return(status: 403, headers: { "Content-Type" => "application/json", "x-ratelimit-remaining" => "0" },
                 body: { message: "API rate limit exceeded" }.to_json)

    error = assert_raises(PublicRepositoryService::TransportError) do
      PublicRepositoryService.resolve("https://github.com/rails/rails")
    end
    assert_match(/rate limit/, error.message)
  end

  test "raises TransportError when the host cannot be reached" do
    stub_request(:get, "https://api.github.com/repos/rails/rails").to_timeout

    assert_raises(PublicRepositoryService::TransportError) do
      PublicRepositoryService.resolve("https://github.com/rails/rails")
    end
  end

  # ====== GitLab ======

  test "resolves a public gitlab project including subgroups" do
    stub_request(:get, "https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { path_with_namespace: "group/sub/app", visibility: "public",
                         default_branch: "trunk", description: "Nested" }.to_json)

    result = PublicRepositoryService.resolve("https://gitlab.com/group/sub/app")

    assert_equal "gitlab", result.provider
    assert_equal "group/sub/app", result.full_name
    assert_equal "trunk", result.default_branch
    assert_equal "https://gitlab.com/group/sub/app.git", result.clone_url
  end

  test "strips a gitlab /-/ deep link before resolving" do
    stub_request(:get, "https://gitlab.com/api/v4/projects/group%2Fapp")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { path_with_namespace: "group/app", visibility: "public", default_branch: "main" }.to_json)

    assert_equal "group/app", PublicRepositoryService.resolve("https://gitlab.com/group/app/-/tree/main").full_name
  end

  test "raises NotPublic for an internal gitlab project" do
    stub_request(:get, "https://gitlab.com/api/v4/projects/group%2Fapp")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { path_with_namespace: "group/app", visibility: "internal", default_branch: "main" }.to_json)

    assert_raises(PublicRepositoryService::NotPublic) do
      PublicRepositoryService.resolve("https://gitlab.com/group/app")
    end
  end

  # ====== Bitbucket ======

  def stub_bitbucket_repository(path, status: 200, body: nil)
    stub_request(:get, "https://api.bitbucket.org/2.0/repositories/#{path}")
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: (body || { type: "error", error: { message: "Repository acme/app not found" } }).to_json)
  end

  test "resolves a public bitbucket repository, even from a /src/ deep link" do
    stub_bitbucket_repository("atlassian/python-bitbucket", body: {
      type: "repository", full_name: "atlassian/python-bitbucket", is_private: false,
      mainbranch: { type: "branch", name: "master" }, description: "Bitbucket API client"
    })

    result = PublicRepositoryService.resolve("https://bitbucket.org/atlassian/python-bitbucket/src/master/README.md")

    assert_equal "bitbucket", result.provider
    assert_equal "atlassian/python-bitbucket", result.full_name
    assert_equal "master", result.default_branch
    assert_equal "https://bitbucket.org/atlassian/python-bitbucket.git", result.clone_url
    assert_equal "Bitbucket API client", result.description
  end

  test "a private bitbucket repository answers anonymously with a refusal, reported as not found or not public" do
    stub_bitbucket_repository("acme/app", status: 403)

    assert_raises(PublicRepositoryService::NotFound) { PublicRepositoryService.resolve("bitbucket.org/acme/app") }
  end

  test "a bitbucket repository flagged private is refused" do
    stub_bitbucket_repository("acme/app", body: { full_name: "acme/app", is_private: true })

    assert_raises(PublicRepositoryService::NotPublic) { PublicRepositoryService.resolve("https://bitbucket.org/acme/app") }
  end

  test "the resolved bitbucket repository attaches as an anonymous public source" do
    stub_bitbucket_repository("acme/app", body: { full_name: "acme/app", is_private: false, mainbranch: { name: "main" } })
    attributes = PublicRepositoryService.resolve("https://bitbucket.org/acme/app").to_repository_attributes

    repository = Repository.new(attributes.merge(scope: create(:project, :standalone)))

    assert repository.valid?, repository.errors.full_messages.to_sentence
    assert_equal "bitbucket", repository.provider
  end

  # ====== Host allowlist ======

  test "refuses hosts that are neither github.com nor gitlab.com" do
    [
      "https://github.evil.com/rails/rails",
      "https://git.internal/acme/app",
      "https://bitbucket.org.evil.com/acme/app",
      "http://169.254.169.254/latest/meta-data",
      "ssh://github.com/rails/rails"
    ].each do |input|
      assert_raises(PublicRepositoryService::UnsupportedHost, input) { PublicRepositoryService.resolve(input) }
    end
  end

  test "refuses http urls on an allowlisted host" do
    assert_raises(PublicRepositoryService::UnsupportedHost) do
      PublicRepositoryService.resolve("http://github.com/rails/rails")
    end
  end

  test "refuses input that is not a repository" do
    [ "", "   ", "https://github.com", "https://github.com/rails", "rails" ].each do |input|
      assert_raises(PublicRepositoryService::UnsupportedHost, input.inspect) do
        PublicRepositoryService.resolve(input)
      end
    end
  end

  test "refuses owner or repo names with shell or path characters" do
    assert_raises(PublicRepositoryService::UnsupportedHost) do
      PublicRepositoryService.resolve("https://github.com/rails/rails;rm -rf /")
    end
  end

  private

  def stub_github(full_name, private: false, default_branch: "main", description: nil)
    stub_request(:get, "https://api.github.com/repos/#{full_name}")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { full_name: full_name, private: private, default_branch: default_branch,
                description: description, clone_url: "https://github.com/#{full_name}.git" }.to_json
      )
  end
end
