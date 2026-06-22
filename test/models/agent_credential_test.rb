# frozen_string_literal: true

require "test_helper"

class AgentCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  # --- Auto-set default on creation ---

  test "first credential sets user default_agent_credential" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")

    @user.reload
    assert_equal credential.id, @user.default_agent_credential_id
  end

  test "subsequent credential updates user default_agent_credential" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")

    @user.reload
    assert_equal second.id, @user.default_agent_credential_id
  end

  # --- Reassign on deletion ---

  test "deleting default credential falls back to most recent remaining" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @user.reload.default_agent_credential_id

    second.destroy!

    @user.reload
    assert_equal first.id, @user.default_agent_credential_id
  end

  test "deleting last credential sets default to nil" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")
    assert_equal credential.id, @user.reload.default_agent_credential_id

    credential.destroy!

    @user.reload
    assert_nil @user.default_agent_credential_id
  end

  test "deleting non-default credential does not change default" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @user.reload.default_agent_credential_id

    first.destroy!

    @user.reload
    assert_equal second.id, @user.default_agent_credential_id
  end

  # --- from_artifacts: clean replacement + preserved preferences ---

  test "from_artifacts fully replaces config_data (no merge with previous auth)" do
    AgentCredential.from_artifacts(@user.id, "claude_code", { "primaryApiKey" => "sk-old", "oauthAccount" => { "id" => "a" } })

    cred = AgentCredential.from_artifacts(@user.id, "claude_code", { "claudeAiOauth" => { "accessToken" => "sk-ant-new" } })

    assert_equal({ "claudeAiOauth" => { "accessToken" => "sk-ant-new" } }, cred.config_data)
    refute cred.config_data.key?("primaryApiKey")
    refute cred.config_data.key?("oauthAccount")
  end

  test "from_artifacts preserves user default_model across re-auth" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => "claude-opus-4-8"))

    updated = AgentCredential.from_artifacts(@user.id, "claude_code", { "primaryApiKey" => "sk-fresh" })

    assert_equal "claude-opus-4-8", updated.metadata["default_model"]
    assert_equal({ "primaryApiKey" => "sk-fresh" }, updated.config_data)
  end

  # --- Model cache invalidation ---

  test "models_cache_key is per-credential" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    assert_equal "agent_models/claude_code/#{cred.id}", cred.models_cache_key
  end

  test "changing config_data invalidates the cached model list" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    Rails.cache.write(cred.models_cache_key, [ { model_id: "stale" } ])

    cred.update!(config_data: { "primaryApiKey" => "sk-rotated" })

    assert_nil Rails.cache.read(cred.models_cache_key)
  end

  test "touching last_used_at does not invalidate the cached model list" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    Rails.cache.write(cred.models_cache_key, [ { model_id: "fresh" } ])

    cred.touch(:last_used_at)

    assert_equal [ { model_id: "fresh" } ], Rails.cache.read(cred.models_cache_key)
  end
end
