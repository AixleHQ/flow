# frozen_string_literal: true

require "test_helper"

class Sessions::SecretRedactorTest < ActiveSupport::TestCase
  include SecretLeakAssertions

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

  # --- Values a terminal or a stream broke apart ---

  test "terminal masks every copy of the secret in a recorded session, wrapped and recoloured ones included" do
    raw = recording("claude_code_2.1.310_terminal.log")
    assert_operator recovered(raw), :>=, RECORDED_SECRET.length, "the recording no longer holds the secret"

    assert_no_secret Sessions::SecretRedactor.new([ RECORDED_SECRET ]).terminal(raw)
  end

  test "terminal changes only the secret's own characters, so the replayed screen keeps its layout" do
    raw = recording("claude_code_2.1.310_terminal.log").force_encoding(Encoding::UTF_8)

    masked = Sessions::SecretRedactor.new([ RECORDED_SECRET ]).terminal(raw)

    assert_equal raw.bytesize, masked.bytesize
    changed = raw.bytes.zip(masked.bytes).reject { |before, after| before == after }
    assert_not_empty changed
    assert(changed.all? { |before, after| after == "*".ord && RECORDED_SECRET.include?(before.chr) })
  end

  test "replaces a value split by colour codes and a line wrap with one fingerprint" do
    text = "-H \"X-Api-Key:pxk_l\e[39m\e[K\r\n  \e[6Give_7Hq2ZtR9mWb4Nc8VxL1aPe6Ks3Dy5Fg0Ju\" \"$1\""

    result = Sessions::SecretRedactor.new([ RECORDED_SECRET ]).call(text)

    assert_equal "-H \"X-Api-Key:#{fingerprint(RECORDED_SECRET)}\" \"$1\"", result
  end

  test "masks a long piece of a secret on its own, as a size limit would leave it" do
    result = Sessions::SecretRedactor.new([ RECORDED_SECRET ]).call("body…[truncated] key=#{RECORDED_SECRET[0, 20]}")

    assert_no_secret result
    assert_includes result, "body…[truncated] key="
  end

  test "masks only the whole of a short secret, never a piece of it" do
    redactor = Sessions::SecretRedactor.new([ "hunter22" ])

    assert_equal "hunter is here", redactor.call("hunter is here")
    assert_equal "pw=#{fingerprint('hunter22')}", redactor.call("pw=hunter22")
  end

  # Seen on real sessions: a twelve-character password whose `!` reached the log escaped,
  # leaving the other eleven characters in plain sight.
  test "masks a short secret whose closing punctuation reached the log escaped" do
    redactor = Sessions::SecretRedactor.new([ "Summer2024!" ])

    assert_equal "-p \"#{fingerprint('Summer2024!')}\\!\"", redactor.call("-p \"Summer2024\\!\"")
    assert_equal "Summer was hot in 2024", redactor.call("Summer was hot in 2024")
  end

  test "finds a secret carrying a quote in a transcript's JSON-escaped form" do
    secret = %(pa"ss\\word-with-a-quote-0042)
    line = { "content" => "key=#{secret}" }.to_json

    result = Sessions::SecretRedactor.new([ secret ]).call(line)

    assert_not_includes result, secret.to_json[1..-2]
    assert_includes result, "redacted:sha256"
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

  test "for_session collects the tokens issued on a user's behalf when no config item is attached" do
    UserTokenIssuance.create!(terminal_session: @session, company: @company, project: @project,
                              acting_for_user: @user, tool_name: "github_user_token", provider: "github",
                              token: "ghu_issued_token_abcdef", target_login: "acme")

    redactor = Sessions::SecretRedactor.for_session(@session)

    assert_not_includes redactor.call("push with ghu_issued_token_abcdef"), "ghu_issued_token_abcdef"
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
