# frozen_string_literal: true

require "test_helper"

class WorkspaceSignupTicketTest < ActiveSupport::TestCase
  def token(**over)
    WorkspaceSignupTicket.issue(
      **{ name: "Acme Robotics", email: "dana@acme-robotics.example" }.merge(over)
    )
  end

  def evidence
    LegalAcceptance::Evidence.new(accepted_at: Time.utc(2026, 11, 2, 9, 30, 15.25r), ip_address: "203.0.113.7",
                                  user_agent: "Browser/1.0")
  end

  # The format of links sent before tickets were encrypted.
  def signed_only(answers)
    Rails.application.message_verifier(WorkspaceSignupTicket::PURPOSE).generate(answers, expires_in: 1.hour)
  end

  test "it carries the answers there and back" do
    assert_equal(
      { name: "Acme Robotics", email: "dana@acme-robotics.example", accept_terms: false, acceptance: nil },
      WorkspaceSignupTicket.decode(token)
    )
  end

  test "it carries an acceptance of the terms in force, as it was given" do
    answers = WorkspaceSignupTicket.decode(token(acceptance: evidence))

    assert answers[:accept_terms]
    assert_equal evidence, answers[:acceptance]
  end

  # The box was ticked for text that has since changed, which accepts nothing.
  test "an acceptance of terms that have changed since is dropped" do
    LegalDocument.stubs(:fingerprint).returns("terms_of_use@2020-01-01")
    stale = token(acceptance: evidence)
    LegalDocument.unstub(:fingerprint)

    answers = WorkspaceSignupTicket.decode(stale)

    assert_equal [ false, nil ], answers.values_at(:accept_terms, :acceptance)
  end

  # It sits in somebody's mailbox, and in the logs of every server it passes.
  test "what it carries cannot be read from the link" do
    issued = token(acceptance: evidence)

    # URL-safe Base64 can itself contain "--", so the parts are cut from the end
    # by their fixed lengths (12-byte IV, 16-byte auth tag), as the encryptor does.
    parts = issued.match(/\A(.+)--([\w-]{16})--([\w-]{22})\z/).captures
    decoded = parts.map { |part| Base64.urlsafe_decode64(part) }.join
    refute_includes decoded, "203.0.113.7"
    refute_includes decoded, "dana@acme-robotics.example"
  end

  # The answers travel through somebody's inbox, where they could otherwise be
  # edited on the way back.
  test "an edited ticket is refused" do
    assert_nil WorkspaceSignupTicket.decode("#{token}x")
    assert_nil WorkspaceSignupTicket.decode(token.reverse)
  end

  test "nothing at all is refused" do
    assert_nil WorkspaceSignupTicket.decode(nil)
    assert_nil WorkspaceSignupTicket.decode("")
    assert_nil WorkspaceSignupTicket.decode("not-a-ticket")
  end

  test "a ticket signed for something else is refused" do
    other = Rails.application.message_verifier("something_else").generate({ "email" => "dana@acme.example" })

    assert_nil WorkspaceSignupTicket.decode(other)
  end

  test "it expires" do
    issued = token
    travel WorkspaceSignupTicket::TTL + 1.second

    assert_nil WorkspaceSignupTicket.decode(issued)
  end

  test "it still reads just before it expires" do
    issued = token
    travel WorkspaceSignupTicket::TTL - 1.minute

    assert_not_nil WorkspaceSignupTicket.decode(issued)
  end

  test "a link sent before tickets were encrypted still opens, accepting nothing" do
    answers = WorkspaceSignupTicket.decode(
      signed_only({ "name" => "Acme", "email" => "dana@acme.example", "accepted_terms" => LegalDocument.fingerprint })
    )

    assert_equal [ "Acme", "dana@acme.example", false ], answers.values_at(:name, :email, :accept_terms)
  end

  # Anything else in the payload is not a signup answer and has no business
  # reaching the form — a worker count included, which links sent before the
  # trial ran one worker still carry.
  test "it hands back only the answers the form asked for" do
    smuggled = signed_only({ "name" => "Acme", "email" => "dana@acme.example", "max_sessions" => 5, "role" => "super_admin" })

    assert_equal %i[name email accept_terms acceptance], WorkspaceSignupTicket.decode(smuggled).keys
  end
end
