# frozen_string_literal: true

require "test_helper"

# The callback-URL seam (DESIGN.md §6.6, task 8b decision 6): a session's
# callback addresses come from its runtime. Every hosted runtime answers the
# Settings values unchanged; RunnerRuntime answers the session's proxy
# (Runners::ProxyTest).
class ContainerRuntime::CallbackUrlsTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @session = create(:terminal_session, user: create(:user, company: company))
  end

  HOSTED = {
    mcp: -> { Settings.mcp.server_url },
    agent_credential_sync: -> { Settings.agents.credential_sync_url },
    agent_credential_refresh: -> { Settings.agents.credential_refresh_url },
    git_credentials: -> { Settings.git.credentials_url },
    azure_git_credentials: -> { Settings.azure_devops.git_credentials_url },
    cloud_credentials: -> { Settings.cloud.credentials_url },
    container_assets: -> { Settings.container_asset_host },
    otel: -> { Settings.otel.endpoint }
  }.freeze

  test "a hosted runtime answers every callback with the Settings value, unchanged" do
    session = @session
    expected = HOSTED.transform_values(&:call)

    [ ContainerRuntime::DockerRuntime.allocate, ContainerRuntime::KubernetesRuntime.allocate,
      ContainerRuntime::FakeRuntime.new ].each do |runtime|
      assert_equal expected, runtime.callback_urls(session), runtime.class.name
    end
    assert_equal expected, ContainerRuntime::CallbackUrls.hosted_all
    assert expected.values.all?(&:present?), "every hosted callback has an address"
  end

  test "a hosted session's runtime is the hosted one, so its callbacks are the Settings values" do
    session = @session

    assert_equal Settings.mcp.server_url, ContainerRuntime.for_session(session).callback_url(:mcp, session)
  end

  test "an unknown callback is an error" do
    assert_raises(ArgumentError) { ContainerRuntime::CallbackUrls.hosted(:nope) }
  end
end
