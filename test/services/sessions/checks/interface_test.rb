# frozen_string_literal: true

require "test_helper"

module Sessions
  module Checks
    # Every check Sessions::Monitor runs implements the one interface, and needs only parts
    # the registry knows how to read.
    class InterfaceTest < ActiveSupport::TestCase
      test "every check is a Checks::Base and declares the snapshot parts it needs" do
        Monitor::CHECKS.each do |check|
          assert_operator check, :<, Base, check.name
          assert_predicate check.parts, :any?, check.name
          check.parts.each { |part| assert_includes Snapshot::Parts::NAMES, part, check.name }
        end
      end

      test "the checks run in today's order of precedence" do
        assert_equal [ QuotaError, BlockingPrompt, AuthPause, TurnEnd, NoOutput ], Monitor::CHECKS
      end

      test "no two checks keep the same key" do
        keys = Monitor::CHECKS.flat_map(&:kept_keys)

        assert_equal keys.uniq, keys
      end

      test "the base class leaves the interface to its subclasses" do
        assert_raises(NotImplementedError) { Base.applies_to?(TerminalSession.new) }
        assert_raises(NotImplementedError) { Base.parts }
      end
    end

    class KeptStateTest < ActiveSupport::TestCase
      setup do
        @session = create(:terminal_session, user: create(:user, :with_company),
                                             metadata: { "turn_end_screen" => "old", "step_name" => "Build" })
      end

      test "collects a pass's changes and writes them in one update that leaves other keys alone" do
        state = KeptState.new(@session)
        view = state.for(TurnEnd)
        view.store(TurnEnd::SEEN_AT_KEY => "now")
        view.delete(TurnEnd::SCREEN_KEY)
        TerminalSession.find(@session.id).merge_jsonb!(:metadata, "other_writer" => true)

        assert_nil view[TurnEnd::SCREEN_KEY]
        assert_equal "now", view[TurnEnd::SEEN_AT_KEY]
        assert_queries_count(1) { assert state.write! }

        metadata = @session.reload.metadata
        assert_equal "now", metadata[TurnEnd::SEEN_AT_KEY]
        refute metadata.key?(TurnEnd::SCREEN_KEY)
        assert_equal "Build", metadata["step_name"]
        assert metadata["other_writer"], "a key another writer set meanwhile is kept"
      end

      test "writes nothing when nothing changed" do
        assert_no_queries { refute KeptState.new(@session).write! }
      end

      test "a check cannot write a key it does not own" do
        view = KeptState.new(@session).for(TurnEnd)

        assert_raises(ArgumentError) { view.store("screen_digest" => "x") }
        assert_raises(ArgumentError) { view["auth_paused_at"] }
      end
    end
  end
end
