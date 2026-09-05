# frozen_string_literal: true

namespace :session_admission do
  desc "Verify reviewed legacy quotas from QUOTA_ALLOWLIST JSON [{namespace, uid}]; deletes only with APPLY=true"
  task remove_legacy_quotas: :environment do
    entries = JSON.parse(File.read(ENV.fetch("QUOTA_ALLOWLIST")))
    raise ArgumentError, "Allowlist must be an array" unless entries.is_a?(Array)
    runtime = ContainerRuntime.build
    raise "Kubernetes runtime required" unless runtime.is_a?(ContainerRuntime::KubernetesRuntime)
    apply = ENV["APPLY"] == "true"
    entries.each do |entry|
      quota = runtime.remove_managed_session_quota(namespace: entry.fetch("namespace"), uid: entry.fetch("uid"), dry_run: !apply)
      if apply
        puts "Requested deletion of reviewed quota in #{entry.fetch('namespace')}"
      else
        puts "Verified #{entry.fetch('namespace')}/aixle-resource-quota uid=#{quota.metadata.uid} hard=#{quota.spec.hard.to_h}"
      end
    end
    puts "Dry run only — nothing was deleted. Re-run with APPLY=true once the report is reviewed." unless apply
  end

  desc "Synchronize deployment concurrency settings (requires drained legacy sessions/runs)"
  task sync: :environment do
    # Scope defaults are read live at grant time and fall back quietly on a bad
    # value so a typo cannot wedge the queue. This is the one place that can
    # afford to be strict about them, so it is.
    SessionAdmissionPolicy::SCOPE_DEFAULTS.each_value do |config|
      raw = ENV[config[:variable]].to_s.strip
      next if raw.empty?
      SessionAdmissionPolicy.positive_integer!(raw)
    end
    policy = SessionAdmissionActivation.call
    if policy.installation_limit
      puts "Session admission enabled: one installation-wide queue of #{policy.installation_limit} concurrent sessions (revision #{policy.revision})."
    else
      # No installation cap means every project and project-less user gets its
      # own queue. Print what that actually resolves to: on an installation that
      # has been running uncapped, the defaults are a capacity cut, not a no-op.
      puts "Session admission enabled with per-scope queues (revision #{policy.revision}):"
      defaults = SessionAdmissionPolicy.scope_defaults
      puts "  every project: #{defaults['Project']} concurrent sessions"
      puts "  every project-less session (agent login): #{defaults['User']} per user"
      overrides = SessionConcurrencyLimit.order(:scope_type, :scope_id)
      if overrides.any?
        overrides.each { |limit| puts "  #{limit.scope_type} ##{limit.scope_id}: #{limit.max_sessions}" }
      else
        puts "  no scope overrides — everything is on the defaults above"
      end
    end
  end

  desc "Pause new admissions; running sessions keep their slots"
  task pause: :environment do
    SessionAdmissionService.transaction do |policy|
      policy.update!(paused: true, revision: policy.revision + 1)
    end
    puts "Admission paused. Queued requests are kept; occupied slots are untouched."
  end

  desc "Resume admissions after a pause without touching caps"
  task resume: :environment do
    SessionAdmissionService.transaction do |policy|
      policy.update!(paused: false, revision: policy.revision + 1)
    end
    granted = SessionAdmissionService.drain!
    puts "Admission resumed. Granted #{granted.size} queued request(s)."
  end

  desc "Display queue and retained reservations without runtime mutations"
  task status: :environment do
    puts JSON.pretty_generate(SessionAdmissionReconciler.snapshot)
    SessionAdmissionPool.order(:id).each do |pool|
      puts "#{pool.key}: limit=#{pool.limit} occupied=#{pool.session_admissions.occupied.count} queued=#{pool.session_admissions.unreleased.where(admitted_at: nil).count}"
    end
    SessionAdmission.occupied.where.not(last_error: nil).each do |admission|
      puts "Admission #{admission.id}, session #{admission.terminal_session_id}: #{admission.last_error}"
    end
  end

  desc "Set a scoped limit: session_admission:set_limit[Project,123,4] (or User)"
  task :set_limit, [ :scope_type, :scope_id, :max_sessions ] => :environment do |_task, args|
    raise ArgumentError, "Scope must be Project or User" unless %w[Project User].include?(args.scope_type)
    id = SessionAdmissionPolicy.positive_integer!(args.scope_id)
    maximum = SessionAdmissionPolicy.positive_integer!(args.max_sessions)
    SessionConcurrencyLimit.set!(scope: args.scope_type.constantize.find(id), max_sessions: maximum)
  end
end
