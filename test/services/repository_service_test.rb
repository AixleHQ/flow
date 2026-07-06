# frozen_string_literal: true

require "test_helper"

# Sociable tests (testing doctrine R5) for the RepositoryService factory: real
# Integration records built with FactoryBot dispatch to the real provider-
# specific service. The subclasses only stash the integration in initialize
# (no network on construction), so the outcome under test is the concrete class
# returned for each provider.
class RepositoryServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  test "for github integration returns a Github::RepositoryService" do
    integration = create(:integration, :github, company: @company, connected_by: @user)

    service = RepositoryService.for(integration)

    assert_instance_of Github::RepositoryService, service
  end

  test "for gitlab integration returns a Gitlab::RepositoryService" do
    integration = create(:integration, :gitlab, company: @company, connected_by: @user)

    service = RepositoryService.for(integration)

    assert_instance_of Gitlab::RepositoryService, service
  end

  test "for an unsupported provider raises with the provider name" do
    integration = create(:integration, :linear, company: @company, connected_by: @user)

    error = assert_raises(RuntimeError) { RepositoryService.for(integration) }
    assert_equal "Unsupported provider: linear", error.message
  end
end
