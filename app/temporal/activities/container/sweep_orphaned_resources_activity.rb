# frozen_string_literal: true

# Activities::Container::SweepOrphanedResourcesActivity
# Deletes the runtime objects of agent sessions that are over — the garbage
# collector behind `Workflows::ContainerSweepOrphanedResourcesWorkflow`
# (`app/temporal/schedules.yml`, every 10 minutes).
#
# WHY IT EXISTS
# A session's Pod, Service, IngressRoute and Middlewares are torn down in
# `ContainerRuntime#remove_container`, which only runs on the happy path. When a
# node dies and takes its agent pods with it, nothing tears anything down: the
# routing objects survive, the Service keeps zero endpoints, and the session URL
# starts answering with Traefik's own "no available server" 503 instead of a
# terminal. Prod reached 22 IngressRoutes against 7 live pods, the oldest orphan
# 16 hours old. Nothing reclaimed them, because nothing was looking.
#
# SAFETY
# The sweep may only delete what it can PROVE nobody is using. Three independent
# guards have to agree before an object is touched:
#
#   1. Provable owner. Reconciliation is by `route_token`, which the runtime
#      stamps on every object of a session (`aixle-container` label → pod name
#      `terminal-<route_token>`) and which is uniquely indexed on
#      `terminal_sessions`. An object whose token is missing or unparseable —
#      an internal-tool pod, a hand-made object — has no provable owner and is
#      always kept.
#   2. Dead owner. The owning session must be in a terminal state (`finished`,
#      `failed`) or absent from the database entirely. Every live state —
#      `not_started`, `running`, `ready`, `finishing` — is kept, so a session
#      that is merely slow (a long `not_started` while an image pulls, a
#      long-running agent, a hung finalization) is never a candidate. Note the
#      ordering that makes this hold: the session row is created, and its
#      route_token generated, BEFORE any container is asked for — so an object
#      can never exist ahead of the row that would protect it.
#   3. Minimum age, twice. The OBJECT must itself be older than MIN_AGE
#      (measured from the runtime's own creation timestamp, so an object created
#      seconds ago during session startup can never qualify), and a
#      terminal-state session's finalization must ALSO be older than MIN_AGE, so
#      an in-flight `remove_container` is never raced. An object whose age the
#      runtime cannot report is kept.
#
# The asymmetry is deliberate: keeping garbage costs a Service with no
# endpoints until the next run, while deleting a live session's IngressRoute
# kills someone's terminal mid-task. Every ambiguous case therefore resolves to
# "keep".
#
# SCOPE
# Only objects the runtime labelled as belonging to a session are enumerated
# (see `KubernetesRuntime::SESSION_RESOURCE_SELECTOR`). Objects created before
# that labelling was uniform — in particular Services, which carried no metadata
# labels at all — are invisible here and remain a one-off operator cleanup.

module Activities
  module Container
    class SweepOrphanedResourcesActivity < ::Activities::Base
      # A session in any of these states may still be using its objects.
      LIVE_STATES = %w[not_started running ready finishing].freeze

      # Startup takes tens of seconds (pod schedule + image pull + readiness +
      # Traefik route propagation), and teardown is a handful of API calls. Fifteen
      # minutes is an order of magnitude clear of both, which is the point: the
      # guard is not a tuned deadline, it is a margin wide enough that no normal
      # timing can land inside it.
      MIN_AGE = 15.minutes

      def run(_input = nil)
        cutoff = MIN_AGE.ago
        resources = Array(runtime.list_session_resources)

        aged, young = resources.partition { |resource| aged?(resource, cutoff) }
        owned, unowned = aged.partition { |resource| resource.route_token.present? }
        sessions = sessions_for(owned)

        reapable, kept = owned.partition { |resource| reapable?(sessions[resource.route_token], cutoff) }
        # Everything in `kept` has a session row — a missing one is reapable —
        # so the split below is safe to index without a nil guard.
        live, finalizing = kept.partition { |resource| LIVE_STATES.include?(sessions[resource.route_token].state) }

        deleted, failed = reap(reapable, sessions)

        summary = {
          reaped: deleted.values.sum,
          by_kind: deleted,
          sessions: reapable.map(&:route_token).uniq.size,
          kept_live: live.size,
          kept_finalizing: finalizing.size,
          kept_recent: young.size,
          kept_unowned: unowned.size,
          failed: failed
        }

        log(:info, "orphan sweep: #{format_summary(summary)}")
        summary
      end

      private

      # One grep-able line per run, so the next incident starts from "what did
      # the sweep think" instead of from a cluster diff.
      def format_summary(summary)
        counts = summary.except(:by_kind).map { |key, value| "#{key}=#{value}" }
        kinds = summary[:by_kind].sort.map { |kind, count| "#{kind}:#{count}" }
        counts << "kinds=#{kinds.join(',')}" if kinds.any?
        counts.join(" ")
      end

      # Guard 3a: the object's own age, as the runtime reports it. A resource
      # whose creation time is unknown is not aged — it is unprovable, so kept.
      def aged?(resource, cutoff)
        resource.created_at.present? && resource.created_at < cutoff
      end

      # Guards 2 + 3b. `nil` means no row owns these objects any more, which is
      # the node-died case the sweep exists for.
      def reapable?(session, cutoff)
        return true if session.nil?
        return false if LIVE_STATES.include?(session.state)

        finalized_at = session.finished_at || session.updated_at
        finalized_at.present? && finalized_at < cutoff
      end

      def sessions_for(resources)
        tokens = resources.map(&:route_token).uniq
        return {} if tokens.empty?

        TerminalSession
          .where(route_token: tokens)
          .select(:id, :route_token, :state, :finished_at, :updated_at)
          .index_by(&:route_token)
      end

      # `resources` arrives in the runtime's promised deletion order — routing
      # objects before the workload they point at — so it is deleted front to
      # back without re-sorting.
      def reap(resources, sessions)
        deleted = Hash.new(0)
        failed = 0

        resources.each do |resource|
          reason = sessions[resource.route_token] ? "session #{sessions[resource.route_token].id} over" : "no session row"

          if runtime.delete_session_resource(resource)
            deleted[resource.kind] += 1
            log(:info, "reaped #{resource} for #{resource.route_token} (#{reason})")
          else
            failed += 1
            log(:warn, "failed to reap #{resource} for #{resource.route_token} (#{reason})")
          end
        rescue StandardError => e
          failed += 1
          log(:warn, "failed to reap #{resource}: #{e.class}: #{e.message}")
        end

        [ deleted, failed ]
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
