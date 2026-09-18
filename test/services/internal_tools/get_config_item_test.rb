# frozen_string_literal: true

require "test_helper"

class InternalTools::GetConfigItemTest < ActiveSupport::TestCase
  setup do
    # Handing out a secret arms the container's log filters first, so every test here
    # runs against a container that can take the list — which is the production shape:
    # this tool is only ever called from inside a live session.
    @runtime = stub_container_runtime
    @company = create(:company)
    @user    = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project,
                                                                  agent_type: "claude_code")
  end

  teardown { cleanup_runtime_overrides }

  def run_tool(params = {})
    InternalTools::GetConfigItem.new(params: params, session: @session).execute
  end

  def attach(item)
    @session.config_items << item
    @session.reload
    item
  end

  test "returns the plaintext value of an attached variable" do
    attach(create(:config_item, :variable, scope: @project, name: "API_BASE", value: "https://api.test"))

    result = run_tool(name: "API_BASE")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "API_BASE", payload["name"]
    assert_equal "variable", payload["item_type"]
    assert_equal "https://api.test", payload["value"]
    assert_nil payload["note"]
  end

  test "returns the decrypted value of an attached secret with a handling note" do
    attach(create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123"))

    result = run_tool(name: "STRIPE_KEY")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "sk_live_abc123", payload["value"]
    assert_equal "secret", payload["item_type"]
    assert_match(/do not echo it/, payload["note"])
  end

  test "matches the name case-insensitively" do
    attach(create(:config_item, :variable, scope: @project, name: "API_BASE", value: "https://api.test"))

    result = run_tool(name: "api_base")

    assert_equal 0, result[:exit_code]
    assert_equal "https://api.test", JSON.parse(result[:stdout])["value"]
  end

  test "refuses an item that exists in the project but is not attached" do
    create(:config_item, :secret, scope: @project, name: "UNATTACHED_KEY", value: "sk_secret")
    attach(create(:config_item, :variable, scope: @project, name: "API_BASE", value: "https://api.test"))

    result = run_tool(name: "UNATTACHED_KEY")

    assert_equal 1, result[:exit_code]
    assert_match(/not available to this session/, result[:stderr])
    assert_not_includes result.values.join, "sk_secret"
    # The recovery hint names what IS reachable — those names are project-public.
    assert_match(/API_BASE/, result[:stderr])
  end

  test "refuses an item from another project even when its name matches" do
    other_project = create(:project, company: @company, owner: @user)
    create(:config_item, :secret, scope: other_project, name: "SHARED_NAME", value: "other_projects_secret")

    result = run_tool(name: "SHARED_NAME")

    assert_equal 1, result[:exit_code]
    assert_not_includes result.values.join, "other_projects_secret"
  end

  test "writes exactly one audit row per successful fetch, without the value" do
    attach(create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123"))

    assert_difference -> { ConfigItemAccess.count }, 1 do
      run_tool(name: "STRIPE_KEY")
    end

    access = ConfigItemAccess.last
    assert_equal "STRIPE_KEY", access.config_item_name
    assert_equal "secret", access.item_type
    assert_equal @session.id, access.terminal_session_id
    assert_equal @user.id, access.user_id
    assert_not_includes access.attributes.values.map(&:to_s).join(" "), "sk_live_abc123"
  end

  test "writes no audit row when the item is not available" do
    create(:config_item, :secret, scope: @project, name: "UNATTACHED_KEY", value: "sk_secret")
    attach(create(:config_item, :variable, scope: @project, name: "API_BASE"))

    assert_no_difference -> { ConfigItemAccess.count } do
      run_tool(name: "UNATTACHED_KEY")
    end
  end

  test "reports an undecryptable secret instead of an empty value" do
    item = attach(create(:config_item, :secret, scope: @project, name: "ROTATED_KEY", value: "sk_old"))
    # What a key rotation without a recrypt leaves behind: ciphertext the current
    # key cannot verify, which ConfigItem#decrypted_value degrades to nil.
    item.update_column(:encrypted_value, "garbage-from-a-previous-key")

    result = run_tool(name: "ROTATED_KEY")

    assert_equal 1, result[:exit_code]
    assert_match(/could not be decrypted/, result[:stderr])
    assert_match(/Secrets & Variables/, result[:stderr])
  end

  test "refuses a value over the size limit" do
    oversized = "x" * (InternalTools::GetConfigItem::MAX_VALUE_BYTES + 1)
    attach(create(:config_item, :variable, scope: @project, name: "BIG_BLOB", value: oversized))

    result = run_tool(name: "BIG_BLOB")

    assert_equal 1, result[:exit_code]
    assert_match(/over the #{InternalTools::GetConfigItem::MAX_VALUE_BYTES}-byte limit/, result[:stderr])
  end

  test "requires a name" do
    result = run_tool({})

    assert_equal 1, result[:exit_code]
    assert_match(/Pass the `name`/, result[:stderr])
  end

  test "reads items attached through the workflow and the step, not just the session" do
    base = create(:config_item, :variable, scope: @project, name: "BASE_KEY", value: "base-value")
    step_item = create(:config_item, :secret, scope: @project, name: "STEP_KEY", value: "step-value")

    workflow = create(:workflow, scope: @project, config: { "base_config_item_ids" => [ base.id ] })
    step = create(:step, workflow: workflow, config_item_ids: [ step_item.id ])
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @session.update!(session_type: "workflow_step")
    create(:step_run, workflow_run: workflow_run, step: step, terminal_session: @session)
    @session.reload

    assert_equal "base-value", JSON.parse(run_tool(name: "BASE_KEY")[:stdout])["value"]
    assert_equal "step-value", JSON.parse(run_tool(name: "STEP_KEY")[:stdout])["value"]
  end

  # --- Serving rule ---

  test "is served only to a session with config items attached" do
    ctx = Tools::Context.for_session(@session)
    refute Tools::Registry.fetch("get_config_item").inject?(ctx)

    attach(create(:config_item, :variable, scope: @project, name: "API_BASE"))

    assert Tools::Registry.fetch("get_config_item").inject?(Tools::Context.for_session(@session.reload))
  end

  test "is not offered in the tool picker" do
    refute Tools::Registry.fetch("get_config_item").user_attachable
  end

  # --- redaction is armed before the value leaves ---

  test "publishes the secret into the container's redaction list before returning it" do
    attach(create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123"))

    run_tool(name: "STRIPE_KEY")

    written = @runtime.read_file(@session.container_id, Sessions::SecretRegistry::LIST_PATH)
    assert_not_nil written, "the container was never handed a redaction list"
    assert_includes written.split("\n").map { |line| Base64.strict_decode64(line) }, "sk_live_abc123"
  end

  test "refuses a secret when the redaction list could not be armed" do
    attach(create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123"))
    Sessions::SecretRegistry.stubs(:publish!).returns(false)

    result = run_tool(name: "STRIPE_KEY")

    assert_equal 1, result[:exit_code]
    assert_not_includes result.to_s, "sk_live_abc123"
    assert_match(/log redaction could not be armed/, result[:stdout].to_s + result[:stderr].to_s)
  end

  test "still returns a plain variable when the redaction list could not be armed" do
    attach(create(:config_item, :variable, scope: @project, name: "API_BASE", value: "https://api.test"))
    Sessions::SecretRegistry.stubs(:publish!).returns(false)

    result = run_tool(name: "API_BASE")

    assert_equal 0, result[:exit_code]
    assert_equal "https://api.test", JSON.parse(result[:stdout])["value"]
  end
end
