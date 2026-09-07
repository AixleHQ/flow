# frozen_string_literal: true

module ContextBuilders
  # The one rule a non-interactive session cannot get away with skipping: it has
  # to end itself. Nothing else does — the container keeps running, and the
  # workflow step waiting on it keeps waiting, until the stale-session sweeper
  # reaps it half an hour later and records the whole run as a failure.
  #
  # It lives in its own :footer section — below even the bottom-of-context tool
  # listings — because agents were still skipping the call when the same mandate
  # was a subsection buried inside <critical-rules> at the top of a long context.
  # The short pointer up there stays (primacy); this is the recency half, and it
  # spells out the cost of skipping rather than only the instruction.
  class SessionCompletion < Base
    def applicable?
      session.mode == "non_interactive"
    end

    def build
      [ section(
        tag: "session-completion",
        priority: :critical,
        content: mandate,
        position_hint: :footer
      ) ]
    end

    private

    def mandate
      <<~RULES.strip
        ## MANDATORY: how this session ends

        This session does NOT end when you stop writing. It ends ONLY when you call
        one of these two tools:

        - **`finish_session`** — the objective is FULLY met and every deliverable
          exists on disk. Optional `note`: a short summary of what you produced.
        - **`fail_session`** — the objective cannot be met. Required `reason`,
          optional `note`.

        **Calling one of them is the last thing you do, every time. There is no third
        option, and no "I'm done" sentence substitutes for the call.**

        If you end your turn without calling either:
        - the container keeps running and burning budget until a sweeper reaps it,
        - a workflow step waiting on this session stalls for that entire time,
        - your work is recorded as a stale failure instead of as the result it was.

        Call `fail_session` — NOT `finish_session` — whenever ANY of these hold:
        - a required resource is missing (repository, file, credential, API, tool),
        - you produced only part of the deliverables,
        - a critical error blocked the task.

        Partial work is a `fail_session` whose `reason` says what is missing. Reporting
        partial work as success is worse than reporting the failure.
      RULES
    end
  end
end
