# frozen_string_literal: true

require "test_helper"

module Insights
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def service
      Insights::IntegrationService.new(project: @project, connected_by: @user)
    end

    test "connect persists an active project row holding the encrypted token" do
      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = service.connect(ingest_token: "aixle_otel_abc")
      end

      assert integration.persisted?
      assert_equal "insights", integration.provider.to_s
      assert_equal @project, integration.project
      assert_equal @company, integration.company
      assert_equal "active", integration.status.to_s
      assert_equal "Insights", integration.name
      assert_equal @user, integration.connected_by
      assert_equal "aixle_otel_abc", integration.insights_ingest_token
      refute_includes integration.read_attribute(:credentials), "aixle_otel_abc"
    end

    test "connect strips whitespace and reconnect updates the same project row" do
      first = service.connect(ingest_token: "  aixle_otel_first  ")

      second = nil
      assert_no_difference -> { Integration.count } do
        second = service.connect(ingest_token: "aixle_otel_second")
      end

      assert_equal first.id, second.id
      assert_equal "aixle_otel_second", second.reload.insights_ingest_token
    end

    test "different projects have separate connections" do
      other = create(:project, company: @company, owner: @user)
      first = service.connect(ingest_token: "aixle_otel_first")
      second = Insights::IntegrationService.new(project: other, connected_by: @user)
                                            .connect(ingest_token: "aixle_otel_second")

      refute_equal first.id, second.id
      assert_equal [ @project.id, other.id ].sort,
                   Integration.where(provider: :insights).pluck(:project_id).sort
    end

    test "a blank token yields an invalid unsaved record" do
      integration = nil
      assert_no_difference -> { Integration.count } do
        integration = service.connect(ingest_token: "   ")
      end

      assert integration.new_record?
      assert { integration.errors[:ingest_token].present? }
    end
  end
end
