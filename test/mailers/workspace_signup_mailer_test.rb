# frozen_string_literal: true

require "test_helper"

class WorkspaceSignupMailerTest < ActionMailer::TestCase
  test "it sends the link to the address that claimed the workspace" do
    token = WorkspaceSignupTicket.issue(name: "Acme Robotics", email: "dana@acme-robotics.example", max_sessions: 5)

    mail = WorkspaceSignupMailer.confirm(
      email: "dana@acme-robotics.example", workspace_name: "Acme Robotics", token: token
    )

    assert_equal [ "dana@acme-robotics.example" ], mail.to
    assert_equal "Confirm your Aixle Flow workspace", mail.subject
    assert_match "Acme Robotics", mail.body.encoded
  end

  # The link is the entire feature: a mail that carries a path instead of a URL,
  # or loses the token, is a signup nobody can finish.
  test "the link is absolute and carries the ticket" do
    token = WorkspaceSignupTicket.issue(name: "Acme", email: "dana@acme.example", max_sessions: 1)

    mail = WorkspaceSignupMailer.confirm(email: "dana@acme.example", workspace_name: "Acme", token: token)
    href = mail.body.encoded[/href="([^"]+)"/, 1]

    assert href.start_with?("http"), "expected an absolute URL, got #{href.inspect}"
    assert_includes CGI.unescapeHTML(href), "/workspace/confirm"
    query = URI.parse(CGI.unescapeHTML(href)).query
    assert_equal token, URI.decode_www_form(query.to_s).to_h["token"]
  end
end
