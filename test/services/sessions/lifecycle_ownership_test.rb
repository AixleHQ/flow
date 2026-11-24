# frozen_string_literal: true

require "test_helper"

# Only Sessions::Lifecycle fires an event of TerminalSession that changes its state
# (docs/design/session-lifecycle.md, §3.7). AASM's `no_direct_assignment` already makes a
# direct write of `state` raise; this test finds the two things it cannot: an event fired
# from somewhere else, and an `update_all`/`update_column(s)` that sets `state`.
#
# It is a source scan, so it is a heuristic: it can miss a session held in a variable with
# another name. Code review is the second guard, and flags a new violation as [Must].
class Sessions::LifecycleOwnershipTest < ActiveSupport::TestCase
  OWNERS = %w[
    app/models/terminal_session.rb
    app/state_machines/terminal_session_state_machine.rb
    app/services/sessions/lifecycle.rb
  ].freeze

  EVENT_CALLS = [
    /\b(?:start_finishing|mark_ready|expire_suspension|mark_restored|finish_without_request|
        fail_after_finish|mark_suspended|expire_suspended_step)!/x,
    /\b(?:session|terminal_session)\.(?:start|enqueue|cancel|fail|finish)!/
  ].freeze

  # A write that skips the setter, on a line that also mentions a session.
  RAW_STATE_WRITES = /(?:update_all|update_columns?)\(.*\bstate\b/

  test "no code outside Sessions::Lifecycle fires a session state event" do
    offenders = scan { |line| EVENT_CALLS.any? { |pattern| line.match?(pattern) } }

    assert_empty offenders, message_for(offenders, "fires a TerminalSession state event")
  end

  test "no code outside Sessions::Lifecycle writes a session's state past the setter" do
    offenders = scan { |line| line.match?(RAW_STATE_WRITES) && line.match?(/session/i) }

    assert_empty offenders, message_for(offenders, "writes a session's state with update_all/update_column(s)")
  end

  private

  def scan
    Rails.root.glob("app/**/*.rb").filter_map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      next if OWNERS.include?(relative)

      path.each_line.with_index(1).filter_map do |line, number|
        next if line.lstrip.start_with?("#", "def ")

        "#{relative}:#{number}: #{line.strip}" if yield(line)
      end
    end.flatten
  end

  def message_for(offenders, what)
    <<~MESSAGE
      Code outside Sessions::Lifecycle #{what}. A session changes state only through
      Sessions::Lifecycle (docs/design/session-lifecycle.md, §3.7). This test is a source
      scan and can miss a differently named variable; review still flags those as [Must].
      #{offenders.join("\n")}
    MESSAGE
  end
end
