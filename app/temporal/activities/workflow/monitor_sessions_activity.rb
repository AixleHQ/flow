# frozen_string_literal: true

# MonitorSessionsActivity
# One pass of Sessions::Monitor: each live workflow step that some check applies to is read
# once, with one exec, and its snapshot handed to the checks in order (Sessions::Checks):
#
#   - a provider quota stop fails the session (Checks::QuotaError, task #195);
#   - a CLI dialog an automatic session cannot answer fails it (Checks::BlockingPrompt,
#     task #605);
#   - a refused login pauses it until it is renewed (Checks::AuthPause);
#   - an automatic session's agent that ended its turn without `finish_session` is typed a
#     reminder, and failed once it has stopped again after the last one (Checks::TurnEnd,
#     task #208).
#
# A failure goes through SessionService.fail_session_if, which completes the step and wakes
# the session's own container workflow so its cleanup runs, instead of it waiting out its
# 23-hour signal timeout.
#
# One read per session on purpose: the pod-exec handshake is the expensive part of a pass,
# and a second per-minute sweep over the same containers is what previously pinned
# worker-ruby to its HPA ceiling.
module Activities
  module Workflow
    class MonitorSessionsActivity < ::Activities::Base
      def run(_input = nil)
        Sessions::Monitor.new.pass
      end
    end
  end
end
