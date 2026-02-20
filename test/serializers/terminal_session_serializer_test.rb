# frozen_string_literal: true

require "test_helper"

class TerminalSessionSerializerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
  end

  test "ide_url returns base URL without token when metadata lacks vscode_token" do
    session = create(:terminal_session, :running, user: @user, metadata: {})

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    expected = "#{Settings.traefik.http_base}/t/#{session.route_token}/ide/"
    assert_equal expected, data[:ide_url]
    refute data[:ide_url].include?("?tkn=")
  end

  test "ide_url includes tkn param when metadata has vscode_token" do
    token = SecureRandom.hex(32)
    session = create(:terminal_session, :running, user: @user, metadata: { "vscode_token" => token })

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    expected = "#{Settings.traefik.http_base}/t/#{session.route_token}/ide/?tkn=#{token}"
    assert_equal expected, data[:ide_url]
  end

  test "ide_url returns nil when route_token is blank" do
    session = build(:terminal_session, user: @user)
    session.route_token = nil

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    assert_nil data[:ide_url]
  end

  test "websocket_url returns URL with route_token" do
    session = create(:terminal_session, :running, user: @user)

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    expected = "#{Settings.traefik.ws_base}/t/#{session.route_token}/tty/ws"
    assert_equal expected, data[:websocket_url]
  end

  test "watcher_url returns nil for agent_session" do
    session = create(:terminal_session, :running, user: @user, session_type: "agent_session")

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    assert_nil data[:watcher_url]
  end

  test "watcher_url returns URL for auth_setup" do
    session = create(:terminal_session, :running, user: @user, session_type: "auth_setup")

    serializer = TerminalSessionSerializer.new(session)
    data = serializer.serializable_hash

    expected = "#{Settings.traefik.http_base}/t/#{session.route_token}/fs"
    assert_equal expected, data[:watcher_url]
  end
end
