# frozen_string_literal: true

require "test_helper"

class SessionLogTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @session = create(:terminal_session, user: @user)
  end

  # ====== Validations ======

  test "valid session log" do
    log = build(:session_log, terminal_session: @session)
    assert log.valid?
  end

  test "name must be present" do
    log = build(:session_log, terminal_session: @session, name: nil)
    assert_not log.valid?
    assert log.errors[:name].present?
  end

  test "name cannot be blank" do
    log = build(:session_log, terminal_session: @session, name: "")
    assert_not log.valid?
    assert log.errors[:name].present?
  end

  test "terminal_session must be present" do
    log = build(:session_log, terminal_session: nil)
    assert_not log.valid?
    assert log.errors[:terminal_session].present?
  end

  # ====== Associations ======

  test "belongs_to terminal_session" do
    log = create(:session_log, terminal_session: @session)
    assert_equal @session, log.terminal_session
  end

  test "destroyed when terminal_session is destroyed" do
    log = create(:session_log, terminal_session: @session)
    assert_difference "SessionLog.count", -1 do
      @session.destroy!
    end
  end

  # ====== Shrine Attachment ======

  test "accepts file attachment" do
    log = build(:session_log, terminal_session: @session)
    io = StringIO.new("log line 1\nlog line 2\n")
    io.define_singleton_method(:original_filename) { "http.log" }
    log.file = io
    assert log.save
    assert log.file.present?
  end

  # ====== TerminalSession has_many ======

  test "terminal_session has_many session_logs" do
    create(:session_log, terminal_session: @session, name: "http.log")
    create(:session_log, terminal_session: @session, name: "stderr.log")
    assert_equal 2, @session.session_logs.count
  end
end
