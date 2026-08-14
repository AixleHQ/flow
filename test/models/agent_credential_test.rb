# frozen_string_literal: true

require "test_helper"

class AgentCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    # The default agent credential is a per-company property, so it lives on the
    # membership: one separately-billed credential per company.
    @membership = @user.company_memberships.sole
  end

  # --- Auto-set default on creation ---

  test "first credential sets the membership default_agent_credential" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")

    assert_equal credential.id, @membership.reload.default_agent_credential_id
  end

  test "subsequent credential updates the membership default_agent_credential" do
    create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")

    assert_equal second.id, @membership.reload.default_agent_credential_id
  end

  # --- Reassign on deletion ---

  test "deleting default credential falls back to most recent remaining" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @membership.reload.default_agent_credential_id

    second.destroy!

    assert_equal first.id, @membership.reload.default_agent_credential_id
  end

  test "deleting last credential sets default to nil" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")
    assert_equal credential.id, @membership.reload.default_agent_credential_id

    credential.destroy!

    assert_nil @membership.reload.default_agent_credential_id
  end

  test "deleting non-default credential does not change default" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @membership.reload.default_agent_credential_id

    first.destroy!

    @user.reload
    assert_equal second.id, @membership.reload.default_agent_credential_id
  end

  # --- from_artifacts: clean replacement + preserved preferences ---

  test "from_artifacts fully replaces config_data (no merge with previous auth)" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-old", "oauthAccount" => { "id" => "a" } })

    cred = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "claudeAiOauth" => { "accessToken" => "sk-ant-new" } })

    assert_equal({ "claudeAiOauth" => { "accessToken" => "sk-ant-new" } }, cred.config_data)
    refute cred.config_data.key?("primaryApiKey")
    refute cred.config_data.key?("oauthAccount")
  end

  test "from_artifacts preserves user default_model on a token refresh" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => "claude-opus-4-8"))

    updated = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-fresh" })

    assert_equal "claude-opus-4-8", updated.metadata["default_model"]
    assert_equal({ "primaryApiKey" => "sk-fresh" }, updated.config_data)
  end

  test "from_artifacts drops default_model on a new authorization" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge(
      "default_model" => "arn:aws:bedrock:us-east-1:1234:application-inference-profile/abc",
      "google_cloud_project" => "keep-me"
    ))

    updated = AgentCredential.from_artifacts(
      @user.id, @company.id, "claude_code",
      { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-new" } },
      new_authorization: true
    )

    refute updated.metadata.key?("default_model"),
           "a model chosen under the previous auth cannot be invoked by the new one"
    assert_equal "keep-me", updated.metadata["google_cloud_project"],
                 "non-auth settings still survive a new authorization"
  end

  test "from_artifacts on a new authorization is a no-op when no default_model was set" do
    create(:agent_credential, user: @user, agent_type: "claude_code")

    updated = AgentCredential.from_artifacts(
      @user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-fresh" }, new_authorization: true
    )

    refute updated.metadata.key?("default_model")
    assert_equal({ "primaryApiKey" => "sk-fresh" }, updated.config_data)
  end

  # --- Default model ---

  test "default_model returns nil when nothing is pinned" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")

    assert_nil cred.default_model
  end

  test "default_model returns a still-supported pin unchanged" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => "claude-opus-5"))

    assert_equal "claude-opus-5", cred.default_model
  end

  test "default_model maps a retired pin forward without rewriting what is stored" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => "claude-3-7-sonnet-20250219"))

    assert_equal "claude-sonnet-5", cred.default_model,
                 "a pin the vendor retired must resolve to a model that still answers"
    assert_equal "claude-3-7-sonnet-20250219", cred.reload.metadata["default_model"],
                 "the stored choice is left alone — the mapping is a read-time rescue"
  end

  test "default_model leaves a Bedrock inference-profile ARN untouched" do
    arn = "arn:aws:bedrock:us-east-1:1234:application-inference-profile/abc"
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => arn))

    assert_equal arn, cred.default_model
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

  # --- expires_at is derived from the stored token (before_save :sync_expires_at) ---

  # Build a Claude Code config whose OAuth token expires at `time` (epoch-ms, as
  # Claude stores it). ClaudeCodeAdapter#token_expires_at reads this back as ms.
  def claude_config(expires_at:)
    { "claudeAiOauth" => { "accessToken" => "sk-ant-tok", "expiresAt" => (expires_at.to_f * 1000).to_i } }
  end

  test "expires_at is populated from the token expiry, converting epoch-ms to a Time" do
    token_exp = 90.minutes.from_now
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: token_exp))

    assert_not_nil cred.expires_at
    assert_in_delta token_exp.to_i, cred.expires_at.to_i, 2
  end

  test "from_artifacts populates expires_at from the persisted token" do
    token_exp = 30.minutes.from_now
    cred = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", claude_config(expires_at: token_exp))

    assert_in_delta token_exp.to_i, cred.reload.expires_at.to_i, 2
  end

  test "expires_at stays nil when the config carries no token expiry" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: { "primaryApiKey" => "sk-ant" })

    assert_nil cred.expires_at
  end

  test "codex/cursor credentials keep expires_at nil (adapter reports no expiry)" do
    codex = create(:agent_credential, user: @user, agent_type: "codex")
    cursor = create(:agent_credential, user: @user, agent_type: "cursor_cli")

    assert_nil codex.expires_at
    assert_nil cursor.expires_at
  end

  test "changing the stored token recomputes expires_at" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 1.hour.from_now))

    later = 5.hours.from_now
    cred.update!(config_data: claude_config(expires_at: later))

    assert_in_delta later.to_i, cred.reload.expires_at.to_i, 2
  end

  test "re-auth to a tokenless config clears a previously-set expires_at" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 1.hour.from_now))
    assert_not_nil cred.expires_at

    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-ant" })

    assert_nil cred.reload.expires_at
  end

  test "a metadata-only save does not recompute expires_at (guarded on config change)" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 1.hour.from_now))
    # Poison the column bypassing callbacks; a stray recompute would reset it to the
    # token-derived (~1h) value, so the sentinel surviving proves the guard held.
    sentinel = 99.days.from_now
    cred.update_column(:expires_at, sentinel)

    cred.update!(metadata: (cred.metadata || {}).merge("default_model" => "claude-opus-4-8"))

    assert_in_delta sentinel.to_i, cred.reload.expires_at.to_i, 2
  end

  # --- .active becomes meaningful ---

  test "active excludes claude creds whose token already expired and keeps null-expiry creds" do
    expired = create(:agent_credential, user: @user, agent_type: "claude_code",
                                        config_data: claude_config(expires_at: 1.hour.ago))
    null_expiry = create(:agent_credential, user: @user, agent_type: "codex")

    active = AgentCredential.active
    assert_includes active, null_expiry
    refute_includes active, expired
  end

  test "active includes claude creds whose token is still valid" do
    valid = create(:agent_credential, user: @user, agent_type: "claude_code",
                                      config_data: claude_config(expires_at: 1.hour.from_now))

    assert_includes AgentCredential.active, valid
  end

  # --- refreshable / refresh_due scopes (consumed by the token-refresh sweep) ---

  test "refreshable limits to REFRESHABLE_AGENT_TYPES" do
    claude = create(:agent_credential, user: @user, agent_type: "claude_code")
    codex = create(:agent_credential, user: @user, agent_type: "codex")
    cursor = create(:agent_credential, user: @user, agent_type: "cursor_cli")
    gemini = create(:agent_credential, user: @user, agent_type: "gemini_cli")

    refreshable = AgentCredential.refreshable
    assert_includes refreshable, claude
    assert_includes refreshable, codex
    assert_includes refreshable, cursor
    refute_includes refreshable, gemini
  end

  test "refresh_due returns creds expiring within the window, excluding far-future and null-expiry" do
    other = create(:user, company: @company)
    due = create(:agent_credential, user: @user, agent_type: "claude_code",
                                    config_data: claude_config(expires_at: 5.minutes.from_now))
    far = create(:agent_credential, user: other, agent_type: "claude_code",
                                    config_data: claude_config(expires_at: 1.hour.from_now))
    null_expiry = create(:agent_credential, user: @user, agent_type: "codex")

    due_now = AgentCredential.refresh_due
    assert_includes due_now, due
    refute_includes due_now, far
    refute_includes due_now, null_expiry
  end

  test "refresh_due honors a custom window argument" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 45.minutes.from_now))

    refute_includes AgentCredential.refresh_due, cred            # outside default 15m
    assert_includes AgentCredential.refresh_due(1.hour), cred    # inside a 1h window
  end
end
