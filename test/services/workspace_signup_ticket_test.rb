# frozen_string_literal: true

require "test_helper"

class WorkspaceSignupTicketTest < ActiveSupport::TestCase
  def token(**over)
    WorkspaceSignupTicket.issue(
      **{ name: "Acme Robotics", email: "dana@acme-robotics.example", max_sessions: 5 }.merge(over)
    )
  end

  test "it carries the answers there and back" do
    assert_equal(
      { name: "Acme Robotics", email: "dana@acme-robotics.example", max_sessions: 5 },
      WorkspaceSignupTicket.decode(token)
    )
  end

  # The whole point of signing it: the answers travel through somebody's inbox,
  # where they could otherwise be edited on the way back.
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

  # Anything else in the payload is not a signup answer and has no business
  # reaching the form.
  test "it hands back only the answers the form asked for" do
    smuggled = Rails.application.message_verifier(WorkspaceSignupTicket::PURPOSE).generate(
      { "name" => "Acme", "email" => "dana@acme.example", "max_sessions" => 5, "role" => "super_admin" }
    )

    assert_equal %i[name email max_sessions], WorkspaceSignupTicket.decode(smuggled).keys
  end
end
