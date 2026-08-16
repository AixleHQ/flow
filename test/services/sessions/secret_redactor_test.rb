# frozen_string_literal: true

require "test_helper"

class Sessions::SecretRedactorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user    = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  def fingerprint(value)
    "«redacted:sha256:#{Digest::SHA256.hexdigest(value)[0, 8]}»"
  end

  test "replaces a secret with a stable fingerprint and leaves the rest intact" do
    redactor = Sessions::SecretRedactor.new([ "sk_live_abc123" ])

    text = redactor.call("curl -H 'Authorization: Bearer sk_live_abc123' https://api.test")

    assert_not_includes text, "sk_live_abc123"
    assert_includes text, fingerprint("sk_live_abc123")
    assert_includes text, "https://api.test"
  end

  test "redacts a short secret — there is no length floor" do
    # ContextLog::MIN_REDACT_LEN (6) exists because that path registers every MCP
    # header value, secret or not. A value someone marked `secret` is redacted
    # whatever its length.
    redactor = Sessions::SecretRedactor.new([ "pin4" ])

    result = redactor.call("the pin is pin4, remember it")
    assert_not_includes result, "pin4"
    assert_includes result, fingerprint("pin4")
  end

  test "replaces the longer secret first when one contains the other" do
    redactor = Sessions::SecretRedactor.new([ "abc", "abc123" ])

    result = redactor.call("token=abc123")

    assert_equal "token=#{fingerprint('abc123')}", result
  end

  test "returns the text unchanged when there is nothing to redact" do
    assert_equal "plain text", Sessions::SecretRedactor.new([]).call("plain text")
    assert_equal "plain text", Sessions::SecretRedactor.new([ "", nil ]).call("plain text")
  end

  test "handles blank input" do
    redactor = Sessions::SecretRedactor.new([ "secret" ])

    assert_equal "", redactor.call("")
    assert_nil redactor.call(nil)
  end

  # --- Session resolution ---

  test "for_session collects the values of attached secrets only" do
    secret = create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc")
    plain  = create(:config_item, :variable, scope: @project, name: "API_BASE", value: "https://api.test")
    @session.config_items << [ secret, plain ]

    redactor = Sessions::SecretRedactor.for_session(@session.reload)
    result = redactor.call("key=sk_live_abc base=https://api.test")

    assert_not_includes result, "sk_live_abc"
    # A `variable` is not a secret: masking it would only make the log unreadable.
    assert_includes result, "https://api.test"
  end

  test "for_session ignores a secret that is not attached" do
    create(:config_item, :secret, scope: @project, name: "OTHER_KEY", value: "sk_unattached")

    redactor = Sessions::SecretRedactor.for_session(@session)

    refute_predicate redactor, :any?
    assert_equal "sk_unattached", redactor.call("sk_unattached")
  end

  test "for_session resolves through the workflow and step cascade" do
    secret = create(:config_item, :secret, scope: @project, name: "STEP_KEY", value: "sk_step_value")
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, config_item_ids: [ secret.id ])
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @session.update!(session_type: "workflow_step")
    create(:step_run, workflow_run: workflow_run, step: step, terminal_session: @session)

    redactor = Sessions::SecretRedactor.for_session(@session.reload)

    assert_not_includes redactor.call("value=sk_step_value"), "sk_step_value"
  end

  test "for_session on a session with nothing attached is a no-op" do
    refute_predicate Sessions::SecretRedactor.for_session(@session), :any?
    assert_nil Sessions::SecretRedactor.for_session(nil).call(nil)
  end
end
