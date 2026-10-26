# frozen_string_literal: true

require "test_helper"

# Policy (Api::V1::Projects::ChatConnectCodesPolicy): create => project_writable?,
# show => project_accessible?.
class Api::V1::Projects::ChatConnectCodesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    create(:integration, provider: :slack, status: :active, company: @company, project: nil,
                         settings: { "bot_name" => "aixle-flow" })
  end

  teardown { teardown_authz }

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys" }, as: :json
    end
  end

  test "show is a project read" do
    record, _code = ChatConnectCode.issue!(project: @project, provider: "slack", user: @owner, channel: "#deploys")
    assert_project_read(transport: :api) { get api_v1_project_chat_connect_code_path(@project, record), as: :json }
  end
end
