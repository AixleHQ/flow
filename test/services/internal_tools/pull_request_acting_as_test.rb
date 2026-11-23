# frozen_string_literal: true

require "test_helper"

# The write tools of pull_request_* acting as a named member (user_id), through the
# same checks as the *_user_token tools. The pull-request host is the canonical fake;
# the token services are the ones the token tools' tests use.
class InternalTools::PullRequestActingAsTest < ActiveSupport::TestCase
  include PullRequestsTestHelper
  include BitbucketTestHelper

  HEAD = "a" * 40
  HOSTS = %i[github gitlab bitbucket].freeze
  LABELS = { github: "GitHub", gitlab: "GitLab", bitbucket: "Bitbucket" }.freeze

  setup do
    stub_container_runtime
    @company = create(:company)
    @owner = create(:user, :admin, company: @company, name: "Owner")
    @colleague = create(:user, :employee, company: @company, name: "Colleague")
    @project = create(:project, company: @company, owner: @owner)
    create(:project_collaborator, project: @project, user: @colleague)
    @session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    @fake = stub_pull_requests!
  end

  teardown { cleanup_runtime_overrides }

  # Connects `host`: its integration and repository on the session, the colleague's
  # own connected account, and the fake behind the host's token calls.
  def connect!(host)
    @host = host
    case host
    when :github
      Settings.github.stubs(:client_id).returns("Iv1.client")
      Settings.github.stubs(:client_secret).returns("client-secret")
      integration = create(:integration, :github, :active, company: @company)
      @repository = create(:repository, scope: @project, integration: integration, full_name: "AixleHQ/flow")
      Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)
      @credential = create(:oauth_credential, :github_user, owner: @colleague)
      @token = "ghu_fake_scoped_token"
    when :gitlab
      Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
      Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")
      integration = create(:integration, :gitlab, :active, company: @company)
      @repository = create(:repository, scope: @project, integration: integration, full_name: "group/app")
      Gitlab::UserTokenService.stubs(:new).returns(FakeGitlab::UserTokenService.new)
      @credential = create(:oauth_credential, :gitlab_user, owner: @colleague)
      @token = @credential.access_token
    when :bitbucket
      Settings.bitbucket.oauth.stubs(:client_id).returns("bb-cid")
      Settings.bitbucket.oauth.stubs(:client_secret).returns("bb-secret")
      integration = create(:integration, :bitbucket, :active, company: @company, project: @project)
      @repository = create(:repository, :bitbucket, scope: @project, integration: integration, full_name: "acme/api")
      @credential = create(:oauth_credential, :bitbucket_user, owner: @colleague)
      bitbucket = stub_bitbucket!
      bitbucket.user = { uuid: "{6c1f0a4e-0000-4000-8000-0000000000b1}", account_id: "712020:abc",
                         display_name: "Bee Bucket", nickname: "bb-user", avatar_url: nil }
      bitbucket.permissions = { "acme/api" => "write" }
      @token = @credential.access_token
    end
    @session.repositories << @repository
    @fake.add_pull_request(@repository, number: 1, head_sha: HEAD)
  end

  def consent!(user, **flags)
    create(:act_as_consent, user: user, project: @project, provider: @host.to_s, **flags)
  end

  def writes(user_id: nil)
    extra = user_id ? { user_id: user_id } : {}
    {
      create: [ InternalTools::PullRequestCreate, { source_branch: "feature/x", title: "Add x" } ],
      update: [ InternalTools::PullRequestUpdate, { pull_request: "1", title: "New title" } ],
      add_comment: [ InternalTools::PullRequestAddComment, { pull_request: "1", body: "Looks fine" } ],
      review: [ InternalTools::PullRequestReview, { pull_request: "1", verdict: "approve" } ],
      merge: [ InternalTools::PullRequestMerge, { pull_request: "1", expected_head_sha: HEAD } ]
    }.transform_values { |klass, params| [ klass, params.merge(extra) ] }
  end

  def run_write(name, user_id: nil, extra: {})
    klass, params = writes(user_id: user_id).fetch(name)
    klass.new(params: params.merge(extra), session: @session).execute
  end

  def json(result) = JSON.parse(result[:stdout].presence || result[:stderr])

  HOSTS.each do |host|
    label = LABELS.fetch(host)

    test "#{host}: every write tool acts as the connection without user_id" do
      connect!(host)

      writes.each_key do |name|
        result = run_write(name)

        assert_equal 0, result[:exit_code], "#{name}: #{result[:stderr]}"
      end

      assert_nil @fake.acting
      assert_equal [ nil ], PullRequestOperation.pluck(:acting_user_id).uniq
      assert_equal 0, UserTokenIssuance.count
      assert_equal "aixle-bot", @fake.pull_request(@repository, 2).author
    end

    test "#{host}: every write tool acts as the named member with the others-tasks switch" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)

      writes.each_key do |name|
        result = run_write(name, user_id: @colleague.id)

        assert_equal 0, result[:exit_code], "#{name}: #{result[:stderr]}"
        assert_equal @colleague.id, @fake.acting.user_id, name.to_s
        assert_equal @token, @fake.acting.token, name.to_s
      end

      assert_equal [ @colleague.id ], PullRequestOperation.pluck(:acting_user_id).uniq
      assert_equal 5, PullRequestOperation.count
      assert_equal 5, UserTokenIssuance.count
      assert_equal %w[pull_request_add_comment pull_request_create pull_request_merge pull_request_review
                      pull_request_update], UserTokenIssuance.pluck(:tool_name).sort
      assert_equal [ @colleague ], UserTokenIssuance.all.map(&:acting_for_user).uniq
      assert_equal [ @owner ], UserTokenIssuance.all.map(&:session_user).uniq
    end

    test "#{host}: the session's own user needs the own-tasks switch" do
      connect!(host)
      create(:oauth_credential, "#{host}_user".to_sym, owner: @owner, oauth_client: @credential.oauth_client)
      consent!(@owner, in_others_tasks: true)

      refused = run_write(:add_comment, user_id: @owner.id)

      assert_equal "permission_denied", json(refused)["error"]
      assert_match(/their own tasks/, json(refused)["message"])

      ActAsConsent.find_by!(user: @owner, provider: host.to_s).update!(in_own_tasks: true)

      assert_equal 0, run_write(:add_comment, user_id: @owner.id)[:exit_code]
    end

    test "#{host}: a member without the others-tasks switch is refused, and nothing is written" do
      connect!(host)
      consent!(@colleague, in_own_tasks: true)

      writes.each_key do |name|
        result = run_write(name, user_id: @colleague.id)

        assert_equal 1, result[:exit_code]
        assert_equal "permission_denied", json(result)["error"]
        assert_match(/#{label} account to be used in tasks that aren't theirs/, json(result)["message"])
      end

      assert_empty @fake.calls
      assert_equal 0, PullRequestOperation.count
      assert_equal 0, UserTokenIssuance.count
    end

    test "#{host}: a member who is not on the project is refused" do
      connect!(host)
      outsider = create(:user, :employee, company: @company, name: "Outsider")
      create(:oauth_credential, "#{host}_user".to_sym, owner: outsider, oauth_client: @credential.oauth_client)
      consent!(outsider, in_others_tasks: true)

      result = run_write(:create, user_id: outsider.id)

      assert_match(/Outsider is not a member of project/, json(result)["message"])
      assert_empty @fake.calls
    end

    test "#{host}: a member without a connected account is refused" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      @credential.destroy!

      result = run_write(:merge, user_id: @colleague.id)

      assert_match(/Colleague has not connected a #{label} account/, json(result)["message"])
      assert_empty @fake.calls
    end

    test "#{host}: an expired connection asks to be renewed" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      @credential.update!(expires_at: 1.minute.ago, refresh_token: nil)

      result = run_write(:review, user_id: @colleague.id)

      assert_match(/#{label} connection needs to be renewed/, json(result)["message"])
      assert_empty @fake.calls
    end

    test "#{host}: an id that is not a member of the company is refused" do
      connect!(host)
      stranger = create(:user)

      result = run_write(:update, user_id: stranger.id)

      assert_equal "validation_failed", json(result)["error"]
      assert_match(/No member with id/, json(result)["message"])
      assert_empty @fake.calls
    end

    test "#{host}: no token reaches a result or an error" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)

      results = writes.keys.map { |name| run_write(name, user_id: @colleague.id) }
      consent_less = run_write(:create, user_id: @owner.id)

      (results + [ consent_less ]).each do |result|
        assert_not_includes result.to_json, @token
        assert_not_includes result.to_json, @credential.access_token
      end
    end

    test "#{host}: a retried create returns the first pull request and its author" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)

      first = json(run_write(:create, user_id: @colleague.id, extra: { operation_key: "k1" }))
      retry_result = json(run_write(:create, user_id: @colleague.id, extra: { operation_key: "k1" }))

      assert_equal first.dig("pull_request", "number"), retry_result.dig("pull_request", "number")
      assert_equal @fake.acting.login, retry_result.dig("pull_request", "author")
      assert_equal first.dig("pull_request", "author"), retry_result.dig("pull_request", "author")
      assert retry_result["replayed"]
      assert_equal 1, @fake.calls.count { |call| call.name == :create }
    end

    test "#{host}: a retry with the same key cannot change who the write is made as" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      json(run_write(:create, user_id: @colleague.id, extra: { operation_key: "k2" }))

      as_connection = run_write(:create, extra: { operation_key: "k2" })

      assert_equal "conflict", json(as_connection)["error"]
      assert_equal 1, @fake.calls.count { |call| call.name == :create }
    end

    test "#{host}: the person who opened a pull request cannot approve it as the same identity" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      opened = json(run_write(:create, user_id: @colleague.id))
      number = opened.dig("pull_request", "number").to_s
      approve = InternalTools::PullRequestReview

      as_opener = approve.new(params: { pull_request: number, verdict: "approve", user_id: @colleague.id },
                              session: @session).execute
      as_connection = approve.new(params: { pull_request: number, verdict: "approve" }, session: @session).execute

      assert_equal "permission_denied", json(as_opener)["error"]
      assert_match(/cannot approve it/, json(as_opener)["message"])
      assert_equal 0, as_connection[:exit_code]
    end

    test "#{host}: the connection that opened a pull request does not stop a member from approving it" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      opened = json(run_write(:create))

      result = InternalTools::PullRequestReview.new(
        params: { pull_request: opened.dig("pull_request", "number").to_s, verdict: "approve", user_id: @colleague.id },
        session: @session
      ).execute

      assert_equal 0, result[:exit_code]
    end

    test "#{host}: merging as a member still obeys the connection's merge switch" do
      connect!(host)
      consent!(@colleague, in_others_tasks: true)
      @repository.integration.update!(settings: @repository.integration.settings.to_h.merge("pull_request_merge" => false))

      result = run_write(:merge, user_id: @colleague.id)

      assert_equal "permission_denied", json(result)["error"]
      assert_match(/Merging is turned off/, json(result)["message"])
      assert_not @fake.called?(:merge)
    end
  end
end
