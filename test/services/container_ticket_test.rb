# frozen_string_literal: true

require "test_helper"

class ContainerTicketTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "a ticket names its user for its own session only, and only until it expires" do
    ticket = ContainerTicket.issue(user: @user, session: @session)
    other = create(:terminal_session, :agent_session, user: @user, project: @project)

    assert_equal @user, ContainerTicket.user_for(ticket, session: @session)
    assert_nil ContainerTicket.user_for(ticket, session: other)
    assert_nil ContainerTicket.user_for("forged", session: @session)

    travel ContainerTicket::TICKET_TTL + 1.minute do
      assert_nil ContainerTicket.user_for(ticket, session: @session)
    end
  end

  test "a ticket ends with the browser sign-in it was issued in, and passes that on when exchanged" do
    sign_in = UserSession.start!(user: @user)
    Current.user_session = sign_in
    ticket = ContainerTicket.issue(user: @user, session: @session)
    Current.user_session = nil
    cookie = ContainerTicket.issue(user: @user, session: @session,
                                   user_session_id: ContainerTicket.verify(ticket, session: @session)["us"])

    assert_equal @user, ContainerTicket.user_for(cookie, session: @session)

    sign_in.revoke!

    assert_nil ContainerTicket.user_for(ticket, session: @session)
    assert_nil ContainerTicket.user_for(cookie, session: @session)
  end

  test "a ticket stops working when its user can no longer sign in" do
    ticket = ContainerTicket.issue(user: @user, session: @session)
    @user.suspend!

    assert_nil ContainerTicket.user_for(ticket, session: @session)
  end

  test "URLs carry a ticket only when containers are served from a host of their own" do
    url = "https://flow.example.com/t/#{@session.route_token}/tty/ws"
    Settings.stubs(:domain).returns("flow.example.com")

    Settings.traefik.stubs(:http_base).returns("https://flow.example.com")
    assert_equal url, ContainerTicket.append(url, user: @user, session: @session)

    Settings.traefik.stubs(:http_base).returns("https://t.flow.example.com")
    appended = ContainerTicket.append(url, user: @user, session: @session)
    ticket = Rack::Utils.parse_query(URI.parse(appended).query)[ContainerTicket::PARAM]
    assert_equal @user, ContainerTicket.user_for(ticket, session: @session)
  end
end
