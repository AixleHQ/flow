# frozen_string_literal: true

require "test_helper"

module Github
  # Contract tests (testing doctrine R4): the adapter is pinned to the real
  # api.github.com surface with WebMock stub_request + realistic payloads, and the
  # collaborating Github::TokenService is real (R5) with only its token endpoint
  # stubbed. No Octokit constant is mocked.
  #
  # These are the shapes FakeGithub::CheckStatusService hands back, so a drift in
  # what GitHub returns fails here rather than silently in every caller test.
  class CheckStatusServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
      @integration.credentials_data = { "installation_id" => "12345" }
      @integration.save!

      # Worker-unique path (parallel suite): a fixed tmp filename races across
      # forked workers — one worker's teardown deletes the pem another is reading.
      @pem_path = Rails.root.join("tmp", "test-github-check-status-#{Process.pid}.pem")
      File.write(@pem_path, OpenSSL::PKey::RSA.generate(2048).to_pem)
      Settings.github.stubs(:app_id).returns("999")
      Settings.github.stubs(:private_key_path).returns(@pem_path.to_s)

      stub_installation_token("ghs_check_status_token")

      @service = Github::CheckStatusService.new(@integration)
    end

    teardown do
      File.delete(@pem_path) if File.exist?(@pem_path)
    end

    # == pull_request_checks ==

    test "reports a pull request whose check suites all succeeded as completed" do
      stub_pull_request("abc1234def")
      stub_check_suites("abc1234def", [
        { status: "completed", conclusion: "success" },
        { status: "completed", conclusion: "skipped" }
      ])

      result = @service.pull_request_checks("org/app", 42)

      assert result.completed?
      assert_equal "success", result.conclusion
    end

    test "reports the failing conclusion when any check suite failed" do
      stub_pull_request("abc1234def")
      stub_check_suites("abc1234def", [
        { status: "completed", conclusion: "success" },
        { status: "completed", conclusion: "failure" }
      ])

      result = @service.pull_request_checks("org/app", 42)

      assert result.completed?
      assert_equal "failure", result.conclusion
    end

    test "reports a completed check suite with no conclusion as unknown rather than as a pass" do
      stub_pull_request("abc1234def")
      stub_check_suites("abc1234def", [ { status: "completed", conclusion: nil } ])

      result = @service.pull_request_checks("org/app", 42)

      assert result.completed?
      assert_equal "unknown", result.conclusion
      assert_not_includes Gate::PASSING_CONCLUSIONS, result.conclusion
    end

    test "reports a pull request with a running check suite as in_progress" do
      stub_pull_request("abc1234def")
      stub_check_suites("abc1234def", [
        { status: "completed", conclusion: "success" },
        { status: "in_progress", conclusion: nil }
      ])

      result = @service.pull_request_checks("org/app", 42)

      assert result.in_progress?
      assert_match(/1\/2 check suites still running/, result.detail)
    end

    test "reports a pull request with no check suites as unresolvable" do
      stub_pull_request("abc1234def")
      stub_check_suites("abc1234def", [])

      result = @service.pull_request_checks("org/app", 42)

      assert result.unresolvable?
      assert_match(/no check suites/, result.detail)
    end

    test "reports a missing pull request as unresolvable" do
      stub_request(:get, "https://api.github.com/repos/org/app/pulls/42")
        .to_return(status: 404, headers: { "Content-Type" => "application/json" },
                   body: { message: "Not Found" }.to_json)

      result = @service.pull_request_checks("org/app", 42)

      assert result.unresolvable?
      assert_match(/PR #42 not found/, result.detail)
    end

    test "reports a server error as unavailable rather than as a verdict" do
      Rails.logger.stubs(:warn)
      stub_request(:get, "https://api.github.com/repos/org/app/pulls/42")
        .to_return(status: 500, headers: { "Content-Type" => "application/json" },
                   body: { message: "Server Error" }.to_json)

      result = @service.pull_request_checks("org/app", 42)

      assert result.unavailable?
      assert_nil result.conclusion
    end

    # == workflow_run_status ==

    test "reports a completed workflow run with its conclusion" do
      stub_workflow_run(status: "completed", conclusion: "failure")

      result = @service.workflow_run_status("org/app", 987)

      assert result.completed?
      assert_equal "failure", result.conclusion
    end

    test "reports an in-progress workflow run as in_progress" do
      stub_workflow_run(status: "in_progress", conclusion: nil)

      result = @service.workflow_run_status("org/app", 987)

      assert result.in_progress?
      assert_match(/is in_progress/, result.detail)
    end

    test "reports a deleted workflow run as unresolvable" do
      stub_request(:get, "https://api.github.com/repos/org/app/actions/runs/987")
        .to_return(status: 404, headers: { "Content-Type" => "application/json" },
                   body: { message: "Not Found" }.to_json)

      result = @service.workflow_run_status("org/app", 987)

      assert result.unresolvable?
      assert_match(/workflow run 987 not found/, result.detail)
    end

    private

    def stub_installation_token(token)
      stub_request(:post, "https://api.github.com/app/installations/12345/access_tokens")
        .to_return(
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { token: token, repository_selection: "all" }.to_json
        )
    end

    def stub_pull_request(head_sha)
      stub_request(:get, "https://api.github.com/repos/org/app/pulls/42")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { number: 42, state: "open", head: { sha: head_sha, ref: "feature/x" } }.to_json
        )
    end

    def stub_check_suites(head_sha, suites)
      body = {
        total_count: suites.size,
        check_suites: suites.each_with_index.map do |suite, i|
          { id: 100 + i, head_sha: head_sha, status: suite[:status], conclusion: suite[:conclusion] }
        end
      }

      # Regex, not a literal url: Octokit paginates this endpoint, and with
      # auto_paginate on (config/initializers/octokit.rb) it appends per_page=100.
      stub_request(:get, %r{\Ahttps://api\.github\.com/repos/org/app/commits/#{head_sha}/check-suites})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json)
    end

    def stub_workflow_run(status:, conclusion:)
      stub_request(:get, "https://api.github.com/repos/org/app/actions/runs/987")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { id: 987, name: "CI", status: status, conclusion: conclusion }.to_json
        )
    end
  end
end
