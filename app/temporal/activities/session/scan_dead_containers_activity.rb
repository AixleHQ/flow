# frozen_string_literal: true

# ScanDeadContainersActivity
# Watchdog for agent containers that died without telling anyone.
#
# Agent pods are bare pods with `restartPolicy: Never` and no owning controller
# (ContainerRuntime::KubernetesRuntime#build_pod), so when their node dies the pods
# die with it — and nothing in the app notices. The session stays `ready` forever,
# its container workflow keeps awaiting `container_finished` (23-hour signal
# timeout), and the linked StepRun stays `running` with a frozen `updated_at`. In
# production a single node OOM stranded ten sessions this way, the oldest for 16
# hours.
#
# This sweep closes the loop: it asks the runtime whether each active session's
# container is still there, and drives the ones that are not through the existing
# `fail` path (SessionService.fail_session → container_finished → cleanup phase →
# CompleteStepActivity), which is what fails the step and reclaims the pod,
# Service, IngressRoute and Middlewares.
#
# Two guards keep it from firing on healthy sessions:
#
#   MIN_AGE            — a pod that has not been created yet is not a dead pod.
#   CONFIRMATION_DELAY — one look is not enough. The normal teardown path
#                        (ContainerStrategies::BaseStrategy#cleanup) stops and
#                        removes the container while the session is still `ready`
#                        and only transitions it afterwards, so for a few seconds a
#                        perfectly healthy completion is indistinguishable from a
#                        dead node. A session is only failed when it looked dead
#                        twice, CONFIRMATION_DELAY apart.
module Activities
  module Session
    class ScanDeadContainersActivity < Base
      ACTIVE_STATES = %w[running ready].freeze

      # Runtime answers that mean "the agent is gone". `:starting` (pod Pending,
      # docker "created") and `:unknown` (control plane unreachable) never qualify —
      # see ContainerRuntime::BaseRuntime#container_status.
      DEAD_STATUSES = %i[missing terminated].freeze
      ALIVE_STATUSES = %i[running starting].freeze

      # A pod can sit Pending for a while (scheduling, image pull) and reports
      # `:starting` while it does, so this is belt-and-braces rather than the main
      # defence: it only has to cover the moment between persisting `container_id`
      # and the runtime being able to answer for it at all.
      MIN_AGE = 2.minutes

      # Comfortably longer than a normal teardown (stop with a 5s grace, remove,
      # transition — seconds), and short enough that a genuinely dead session is
      # failed within ~3 minutes instead of hanging for a day.
      CONFIRMATION_DELAY = 2.minutes

      MARKER_KEY = "container_dead_since"

      MESSAGES = {
        missing: "Agent container vanished: the container runtime no longer knows this container. " \
                 "Its node most likely died or the pod was evicted.",
        terminated: "Agent container is no longer running: it exited before the session finished. " \
                    "Its node most likely died, or the container was killed (out of memory, eviction)."
      }.freeze

      def run(_input = nil)
        checked = 0
        failed = 0

        candidate_sessions.find_each do |session|
          checked += 1
          status = runtime.container_status(session.container_id)

          if DEAD_STATUSES.include?(status)
            failed += 1 if confirm_or_mark(session, status)
          elsif ALIVE_STATUSES.include?(status)
            clear_marker(session)
          end
        rescue StandardError => e
          log(:warn, "Failed to check session #{session.id}: #{e.message}")
        end

        { checked: checked, failed: failed }
      end

      private

      def candidate_sessions
        TerminalSession
          .where(state: ACTIVE_STATES)
          .where.not(container_id: [ nil, "" ])
          .where("COALESCE(started_at, created_at) < ?", MIN_AGE.ago)
      end

      # First sighting only records the time; the session is failed on a later
      # sighting, once CONFIRMATION_DELAY has passed and it is still both dead and
      # active. Returns true when the session was failed.
      def confirm_or_mark(session, status)
        first_seen = marker_at(session)

        if first_seen.nil?
          mark_dead(session)
          return false
        end

        return false if first_seen > CONFIRMATION_DELAY.ago
        return false unless ACTIVE_STATES.include?(session.reload.state)

        SessionService.fail_session(session: session, error_message: MESSAGES.fetch(status))
        log(:info, "Failed session #{session.id}: container #{status}")
        true
      end

      def marker_at(session)
        raw = session.metadata&.dig(MARKER_KEY)
        return nil if raw.blank?

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def mark_dead(session)
        session.update!(metadata: (session.metadata || {}).merge(MARKER_KEY => Time.current.iso8601))
        log(:info, "Session #{session.id} looks dead; re-checking in #{CONFIRMATION_DELAY.inspect}")
      end

      # A container that came back (or was never really gone — a flapping API read)
      # drops its marker, so confirmation always means two dead sightings with
      # nothing alive in between.
      def clear_marker(session)
        return unless session.metadata.is_a?(Hash) && session.metadata.key?(MARKER_KEY)

        session.update!(metadata: session.metadata.except(MARKER_KEY))
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
