# frozen_string_literal: true

require "test_helper"

module Gitlab
  # Contract test: pins Gitlab::PipelineStatusService against the real GitLab REST
  # API via WebMock stub_request with realistic payloads (testing doctrine R2/R4).
  # The real Gitlab::TokenService + gitlab gem run against a stubbed HTTP boundary —
  # no vendor constant is mocked.
  class PipelineStatusServiceTest < ActiveSupport::TestCase
    GITLAB_API = "https://gitlab.com/api/v4"

    # GitLab percent-encodes "group/app" to "group%2Fapp"; tolerate either form
    # in case the HTTP stack normalizes the encoded slash.
    PIPELINE_URL = %r{\Ahttps://gitlab\.com/api/v4/projects/group(?:%2F|/)app/pipelines/555\z}

    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)

      Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: GITLAB_API))
      @service = Gitlab::PipelineStatusService.new(@integration)
    end

    test "reports a successful pipeline as completed with its status" do
      stub_pipeline(status: "success")

      result = @service.pipeline_status("group/app", 555)

      assert result.completed?
      assert_equal "success", result.conclusion
    end

    test "reports a failed pipeline as completed with the failure status" do
      stub_pipeline(status: "failed")

      result = @service.pipeline_status("group/app", 555)

      assert result.completed?
      assert_equal "failed", result.conclusion
      assert_not_includes Gate::PASSING_CONCLUSIONS, result.conclusion
    end

    test "reports a running pipeline as in_progress" do
      stub_pipeline(status: "running")

      result = @service.pipeline_status("group/app", 555)

      assert result.in_progress?
      assert_match(/is running/, result.detail)
    end

    test "reports a manually blocked pipeline as in_progress, not as a verdict" do
      stub_pipeline(status: "manual")

      result = @service.pipeline_status("group/app", 555)

      assert result.in_progress?
      assert_nil result.conclusion
    end

    test "reports a deleted pipeline as unresolvable" do
      stub_request(:get, PIPELINE_URL)
        .to_return(status: 404, headers: { "Content-Type" => "application/json" },
                   body: { message: "404 Not found" }.to_json)

      result = @service.pipeline_status("group/app", 555)

      assert result.unresolvable?
      assert_match(/pipeline 555 not found/, result.detail)
    end

    test "reports a server error as unavailable" do
      Rails.logger.stubs(:warn)
      stub_request(:get, PIPELINE_URL)
        .to_return(status: 500, headers: { "Content-Type" => "application/json" },
                   body: { message: "500 Internal Server Error" }.to_json)

      result = @service.pipeline_status("group/app", 555)

      assert result.unavailable?
      assert_nil result.conclusion
    end

    private

    def stub_pipeline(status:)
      stub_request(:get, PIPELINE_URL)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { id: 555, project_id: 7, sha: "abc123", ref: "main", status: status }.to_json
        )
    end
  end
end
