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
    # Print what the settings actually resolve to: on an installation that has
    # been running uncapped, the defaults are a capacity cut, not a no-op.
    puts "Session admission enabled (revision #{policy.revision}):"
    puts "  every project: #{SessionAdmissionPolicy.scope_default('Project')} concurrent sessions unless it sets its own"
    puts "  sessions launched outside a project (agent logins) are not queued"
    if policy.installation_limit
      puts "  installation ceiling: #{policy.installation_limit} concurrent sessions across all projects"
    else
      puts "  no installation ceiling — project limits are the only bound"
    end
    overrides = SessionConcurrencyLimit.order(:scope_id)
    if overrides.any?
      overrides.each { |limit| puts "  #{limit.scope_record&.name || limit.scope_type} ##{limit.scope_id}: #{limit.max_sessions}" }
      puts "  allocated: #{overrides.sum(:max_sessions)}#{" of #{policy.installation_limit}" if policy.installation_limit}"
    else
      puts "  no project overrides — everything is on the default above"
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

  desc "Set a project limit: session_admission:set_limit[Project,123,4]"
  task :set_limit, [ :scope_type, :scope_id, :max_sessions ] => :environment do |_task, args|
    raise ArgumentError, "Scope must be Project" unless args.scope_type == "Project"
    id = SessionAdmissionPolicy.positive_integer!(args.scope_id)
    maximum = SessionAdmissionPolicy.positive_integer!(args.max_sessions)
    SessionConcurrencyLimit.set!(scope: args.scope_type.constantize.find(id), max_sessions: maximum)
  end
end
