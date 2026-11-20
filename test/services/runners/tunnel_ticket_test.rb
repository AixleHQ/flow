# frozen_string_literal: true

require "test_helper"

# Runners::TunnelTicket (docs/design/agent-runtimes/runner-relay.md §3.1;
# runner/protocol/PROTOCOL.md §5.11): the ticket a machine opens the interactive
# tunnel with. The relay verifies it with the same key (runner-relay/internal/ticket).
class Runners::TunnelTicketTest < ActiveSupport::TestCase
  KEY = "a-ticket-key-of-32-characters-xx"

  setup do
    company = create(:company)
    @runner = create(:runner, :manual, company: company)
    project = create(:project, :standalone, company: company)
    @machine = create(:runner_environment, runner: @runner)
    @session = create(:terminal_session, :agent_session, user: project.owner, project: project, runner: @runner,
                                                         runner_environment: @machine, mode: "non_interactive",
                                                         initial_prompt: "go")
    @machine.update!(current_session_id: @session.id)
    Settings.runners.relay.stubs(:ticket_key).returns(KEY)
    Runners::TunnelTicket.stubs(:mode).returns("session")
  end

  test "the ticket carries the machine, its runner and the session that holds it, and expires in a minute" do
    now = Time.zone.local(2026, 11, 20, 15, 0, 0)

    issued = Runners::TunnelTicket.issue(environment: @machine, now: now)

    claims = claims_of(issued.ticket)
    assert_equal 1, claims["v"]
    assert_equal @machine.id, claims["e"]
    assert_equal @runner.id, claims["r"]
    assert_equal @session.id, claims["s"]
    assert_equal (now + 60.seconds).to_i, claims["exp"]
    assert_equal now + 60.seconds, issued.expires_at
    assert_match(/\A[A-Za-z0-9_-]{22}\z/, claims["jti"])
  end

  test "the ticket is artun_, the claims and an HMAC-SHA256 of the claims text under the key, in base64url without padding" do
    ticket = Runners::TunnelTicket.issue(environment: @machine).ticket

    assert ticket.start_with?("artun_")
    text, mac = ticket.delete_prefix("artun_").split(".")
    assert_no_match(/[=+\/]/, ticket, "base64url, no padding")
    expected = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", KEY, text), padding: false)
    assert_equal expected, mac
  end

  test "each ticket has an id of its own" do
    ids = Array.new(3) { claims_of(Runners::TunnelTicket.issue(environment: @machine).ticket)["jti"] }

    assert_equal 3, ids.uniq.size
  end

  test "a machine that holds no session gets no ticket" do
    @machine.update!(current_session_id: nil)

    error = assert_raises(Runners::Credentials::Refused) { Runners::TunnelTicket.issue(environment: @machine) }

    assert_equal "no_session", error.reason
  end

  test "a platform without a ticket key issues none, and says the tunnel is not offered" do
    Settings.runners.relay.stubs(:ticket_key).returns("")

    assert_not Runners::TunnelTicket.enabled?
    error = assert_raises(Runners::Credentials::Refused) { Runners::TunnelTicket.issue(environment: @machine) }
    assert_equal "not_found", error.reason
  end

  test "a platform that tells runners nothing about the tunnel issues none" do
    Runners::TunnelTicket.stubs(:mode).returns("")

    assert_not Runners::TunnelTicket.enabled?
    assert_nil Runners::TunnelTicket.config
    assert_raises(Runners::Credentials::Refused) { Runners::TunnelTicket.issue(environment: @machine) }
  end

  test "a mode runners do not know is off" do
    Runners::TunnelTicket.stubs(:mode).returns("always")

    assert_not Runners::TunnelTicket.enabled?
  end

  test "the config the check-in sends is the mode and the path" do
    assert_equal({ "mode" => "session", "path" => "/runner/v1/tunnel" }, Runners::TunnelTicket.config)
  end

  test "the tunnel is off unless a deployment sets RUNNERS_RELAY_TUNNEL_MODE, so nothing changes for a machine until it does" do
    skip "this run sets RUNNERS_RELAY_TUNNEL_MODE" if ENV["RUNNERS_RELAY_TUNNEL_MODE"].present?
    Runners::TunnelTicket.unstub(:mode)

    assert_not Runners::TunnelTicket.enabled?
    assert_nil Runners::TunnelTicket.config
  end

  test "the ticket key is not the key that encrypts runner operations" do
    assert_not_equal Settings.encryption.runners_key, Settings.runners.relay.ticket_key
  end

  private

  def claims_of(ticket)
    JSON.parse(Base64.urlsafe_decode64(ticket.delete_prefix("artun_").split(".").first))
  end
end
