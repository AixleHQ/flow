# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SettingsMemoryTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }
  teardown { teardown_authz }

  test "owner opts into project memory through settings" do
    sign_in_as(@owner)

    Settings.engram.stub(:url, "https://engram.example.test") do
      patch company_project_settings_path(@project), params: { project: { memory_enabled: true } }
    end

    assert @project.reload.memory_enabled
  end

  test "settings expose memory opt-in and deployment availability" do
    sign_in_as(@owner)

    Engram::Client.stub(:configured?, true) do
      get company_project_settings_path(@project)
    end

    assert_inertia_props do |props|
      assert_equal false, props[:project][:memoryEnabled] # rubocop:disable Minitest/RefuteFalse
      assert props[:project][:memoryAvailable]
      assert props[:project][:memoryCanManage]
    end
  end

  test "owner and company admin can enable and disable memory" do
    Engram::Client.stub(:configured?, true) do
      %i[owner admin].each do |role|
        sign_in_as(user_for(role))

        patch company_project_settings_path(@project), params: { project: { memory_enabled: true } }
        assert_redirected_to company_project_settings_path(@project)
        assert @project.reload.memory_enabled

        patch company_project_settings_path(@project), params: { project: { memory_enabled: false } }
        assert_equal false, @project.reload.memory_enabled # rubocop:disable Minitest/RefuteFalse
      end
    end
  end

  test "collaborators and viewers cannot enable memory" do
    Engram::Client.stub(:configured?, true) do
      %i[collaborator viewer].each do |role|
        sign_in_as(user_for(role))

        patch company_project_settings_path(@project), params: { project: { memory_enabled: true } }

        assert_response :redirect
        assert_equal false, @project.reload.memory_enabled # rubocop:disable Minitest/RefuteFalse
        if role == :collaborator
          assert_match(/owner or a company admin/, Array(session["inertia_errors"][:memoryEnabled]).to_sentence)
        end
      end
    end
  end

  test "unavailable service refuses enabling but allows disabling memory" do
    sign_in_as(@owner)

    Engram::Client.stub(:configured?, false) do
      original_name = @project.name
      patch company_project_settings_path(@project), params: {
        project: { name: "Refused change", memory_enabled: true }
      }

      assert_equal false, @project.reload.memory_enabled # rubocop:disable Minitest/RefuteFalse
      assert_match(/unavailable/i, Array(session["inertia_errors"][:memoryEnabled]).to_sentence)
      assert_equal original_name, @project.name

      @project.update!(memory_enabled: true)
      patch company_project_settings_path(@project), params: { project: { memory_enabled: false } }

      assert_equal false, @project.reload.memory_enabled # rubocop:disable Minitest/RefuteFalse
    end
  end

  test "general settings leave an existing memory opt-in unchanged" do
    sign_in_as(@owner)
    @project.update!(memory_enabled: true)

    patch company_project_settings_path(@project), params: { project: { name: "Renamed" } }

    assert @project.reload.memory_enabled
    assert_equal "Renamed", @project.name
  end
end
