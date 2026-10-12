# frozen_string_literal: true

require "test_helper"

module AixleInsights
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
    end

    def service
      AixleInsights::IntegrationService.new(company: @company, connected_by: @user)
    end

    test "connect persists an active company-wide row holding the token" do
      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = service.connect(ingest_token: "aixle_otel_abc")
      end

      assert integration.persisted?
      assert_equal "aixle_insights", integration.provider.to_s
      assert_nil integration.project_id
      assert_equal "active", integration.status.to_s
      assert_equal "Aixle Insights", integration.name
      assert_equal @user, integration.connected_by
      assert_equal "aixle_otel_abc", integration.insights_ingest_token
    end

    test "connect strips surrounding whitespace from the token" do
      integration = service.connect(ingest_token: "  aixle_otel_padded  ")

      assert_equal "aixle_otel_padded", integration.insights_ingest_token
    end

    test "reconnect replaces the token on the same row without a second row" do
      first = service.connect(ingest_token: "aixle_otel_first")

      second = nil
      assert_no_difference -> { Integration.count } do
        second = service.connect(ingest_token: "aixle_otel_second")
      end

      assert_equal first.id, second.id
      assert_equal "aixle_otel_second", second.reload.insights_ingest_token
    end

    test "a blank token yields an invalid, unsaved record with a field error" do
      integration = nil
      assert_no_difference -> { Integration.count } do
        integration = service.connect(ingest_token: "   ")
      end

      assert integration.new_record?
      assert { integration.errors[:ingest_token].present? }
    end
  end
end
