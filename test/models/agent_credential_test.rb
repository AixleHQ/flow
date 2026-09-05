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

  # --- .not_expired scope ---

  test "not_expired excludes claude creds whose token already expired and keeps null-expiry creds" do
    expired = create(:agent_credential, user: @user, agent_type: "claude_code",
                                        config_data: claude_config(expires_at: 1.hour.ago))
    null_expiry = create(:agent_credential, user: @user, agent_type: "codex")

    not_expired = AgentCredential.not_expired
    assert_includes not_expired, null_expiry
    refute_includes not_expired, expired
  end

  test "not_expired includes claude creds whose token is still valid" do
    valid = create(:agent_credential, user: @user, agent_type: "claude_code",
                                      config_data: claude_config(expires_at: 1.hour.from_now))

    assert_includes AgentCredential.not_expired, valid
  end

  # --- refreshable / refresh_due scopes (consumed by the token-refresh sweep) ---

  test "refreshable limits to REFRESHABLE_AGENT_TYPES" do
    claude = create(:agent_credential, user: @user, agent_type: "claude_code")
    codex = create(:agent_credential, user: @user, agent_type: "codex")
    cursor = create(:agent_credential, user: @user, agent_type: "cursor_cli")
    gemini = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    # Grok tokens do expire, but xAI publishes no token endpoint to refresh them
    # server-side — the CLI rotates them in-container and cleanup re-captures the blob.
    grok = create(:agent_credential, user: @user, agent_type: "grok")

    refreshable = AgentCredential.refreshable
    assert_includes refreshable, claude
    assert_includes refreshable, codex
    assert_includes refreshable, cursor
    refute_includes refreshable, gemini
    refute_includes refreshable, grok
  end

  test "refresh_due returns creds expiring within the window, excluding far-future and null-expiry" do
    other = create(:user, company: @company)
    due = create(:agent_credential, user: @user, agent_type: "claude_code",
                                    config_data: claude_config(expires_at: 5.minutes.from_now))
    far = create(:agent_credential, user: other, agent_type: "claude_code",
                                    config_data: claude_config(expires_at: 2.hours.from_now))
    null_expiry = create(:agent_credential, user: @user, agent_type: "codex")

    due_now = AgentCredential.refresh_due
    assert_includes due_now, due
    refute_includes due_now, far
    refute_includes due_now, null_expiry
  end

  test "refresh_due honors a custom window argument" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 90.minutes.from_now))

    refute_includes AgentCredential.refresh_due, cred            # outside default 60m
    assert_includes AgentCredential.refresh_due(2.hours), cred   # inside a 2h window
  end

  test "refresh_due excludes errored credentials" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 5.minutes.from_now))
    cred.mark_refresh_error!("invalid_grant", permanent: true)

    refute_includes AgentCredential.refresh_due, cred
  end

  # --- without_live_session scope (keeps the sweep off tokens a container holds) ---

  test "without_live_session excludes a credential a live session holds" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 5.minutes.from_now))
    create(:terminal_session, user: @user, company_id: cred.company_id,
                              agent_type: "claude_code", state: "running")

    refute_includes AgentCredential.without_live_session, cred
  end

  test "without_live_session ignores sessions that already ended" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 5.minutes.from_now))
    create(:terminal_session, user: @user, company_id: cred.company_id,
                              agent_type: "claude_code", state: "finished")

    assert_includes AgentCredential.without_live_session, cred
  end

  # A session on a different agent holds different token material, so it says nothing
  # about whether this credential is safe to refresh.
  test "without_live_session only counts sessions on the same agent type" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 5.minutes.from_now))
    create(:terminal_session, user: @user, company_id: cred.company_id,
                              agent_type: "codex", state: "running")

    assert_includes AgentCredential.without_live_session, cred
  end

  test "without_live_session only counts sessions belonging to the credential owner" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: claude_config(expires_at: 5.minutes.from_now))
    other = create(:user, company: @company)
    create(:terminal_session, user: other, company_id: cred.company_id,
                              agent_type: "claude_code", state: "running")

    assert_includes AgentCredential.without_live_session, cred
  end

  # --- refresh_if_expiring! (launch-time top-up) ---

  # A session runs about as long as the token lives, so one started on a token with
  # minutes left dies halfway through. The sweep only tops up in the last stretch of
  # a token's life, which is why the launch does its own check.
  def refreshable_claude_config(expires_at:)
    { "claudeAiOauth" => { "accessToken" => "old-tok", "refreshToken" => "old-ref",
                           "expiresAt" => (expires_at.to_f * 1000).to_i } }
  end

  def stub_token_endpoint
    stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
      .to_return(status: 200,
                 body: { access_token: "new-tok", refresh_token: "new-ref", expires_in: 3_600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  test "refresh_if_expiring! leaves a token with plenty of life alone" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: refreshable_claude_config(expires_at: 3.hours.from_now))

    assert_equal :not_needed, cred.refresh_if_expiring!
  end

  test "refresh_if_expiring! tops up a token that would not outlive the session" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: refreshable_claude_config(expires_at: 20.minutes.from_now))
    stub_token_endpoint

    result = cred.refresh_if_expiring!

    assert_equal :refreshed, result[:status]
    assert_equal "new-tok", cred.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  # Rotating while another container runs on these tokens invalidates the copy it is
  # using — one session about to start would take the others down with it.
  test "refresh_if_expiring! defers to a container already holding the tokens" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: refreshable_claude_config(expires_at: 20.minutes.from_now))
    create(:terminal_session, user: @user, company_id: cred.company_id,
                              agent_type: "claude_code", state: "running")

    assert_equal :held, cred.refresh_if_expiring!
    assert_equal "old-tok", cred.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  # The session being launched is the one asking, and its container has not been
  # handed anything yet — it must not block its own top-up.
  test "refresh_if_expiring! ignores the session it is launching for" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code",
                                     config_data: refreshable_claude_config(expires_at: 20.minutes.from_now))
    launching = create(:terminal_session, user: @user, company_id: cred.company_id,
                                          agent_type: "claude_code", state: "running")
    stub_token_endpoint

    result = cred.refresh_if_expiring!(excluding_session_id: launching.id)

    assert_equal :refreshed, result[:status]
  end

  # --- status / refresh error lifecycle ---

  test "mark_refresh_error! increments failure count and records the message" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")

    cred.mark_refresh_error!("network timeout")

    assert_equal "active", cred.status
    assert_equal 1, cred.refresh_failure_count
    assert_equal "network timeout", cred.refresh_error
  end

  test "mark_refresh_error! escalates to error after MAX_REFRESH_FAILURES consecutive failures" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")

    AgentCredential::MAX_REFRESH_FAILURES.times { cred.mark_refresh_error!("transient") }

    assert_equal "error", cred.status
  end

  test "mark_refresh_error! with permanent: true escalates immediately" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")

    cred.mark_refresh_error!("invalid_grant", permanent: true)

    assert_equal "error", cred.status
    assert_equal 1, cred.refresh_failure_count
    assert_equal "invalid_grant", cred.refresh_error
  end

  test "mark_refresh_error! truncates long messages to 500 chars" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")

    cred.mark_refresh_error!("x" * 600)

    assert_equal 500, cred.refresh_error.length
  end

  test "clear_refresh_error! resets status and clears error fields" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.mark_refresh_error!("invalid_grant", permanent: true)
    assert_equal "error", cred.status

    cred.clear_refresh_error!

    assert_equal "active", cred.status
    assert_nil cred.refresh_error
    assert_equal 0, cred.refresh_failure_count
  end

  test "from_artifacts resets status to active on re-authentication" do
    cred = create(:agent_credential, user: @user, agent_type: "claude_code")
    cred.mark_refresh_error!("invalid_grant", permanent: true)
    assert_equal "error", cred.status

    updated = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-new" })

    assert_equal "active", updated.status
    assert_nil updated.refresh_error
    assert_equal 0, updated.refresh_failure_count
  end
end
