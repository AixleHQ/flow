# frozen_string_literal: true

require "test_helper"

# Policy (Api::V1::Projects::ChatChannelsPolicy): index => project_accessible?,
# destroy => project_writable?.
class Api::V1::Projects::ChatChannelsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @slack = create(:integration, provider: :slack, status: :active, company: @company, project: nil)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_chat_channels_path(@project), as: :json }
  end

  test "destroy is a project write" do
    assert_project_write(transport: :api) do |role|
      channel = connect_chat_channel(company: @company, integration: @slack, external_id: "C0#{role.to_s.upcase.first(8).ljust(8, 'X')}")
      delete api_v1_project_chat_channel_path(@project, channel), as: :json
    end
  end
end
