# frozen_string_literal: true

namespace :session_admission do
  desc "Print legacy quotas as a reviewable session limit migration plan"
  task legacy_plan: :environment do
    puts JSON.pretty_generate(SessionQuotaMigration.plan)
  end

  desc "Import reviewed scoped limits from SESSION_LIMIT_PLAN JSON; never overwrites existing limits"
  task import_limits: :environment do
    plan = JSON.parse(File.read(ENV.fetch("SESSION_LIMIT_PLAN")))
    SessionAdmissionService.transaction do
      plan.fetch("overrides").each do |entry|
        raise ArgumentError, "Invalid scope" unless %w[Project User].include?(entry.fetch("scope_type"))
        entry.fetch("scope_type").constantize.find(entry.fetch("scope_id"))
        limit = SessionConcurrencyLimit.find_or_initialize_by(scope_type: entry.fetch("scope_type"), scope_id: entry.fetch("scope_id"))
        limit.update!(max_sessions: SessionAdmissionPolicy.positive_integer!(entry.fetch("max_sessions"))) if limit.new_record?
      end
    end
    puts "Scoped overrides imported. Apply reviewed defaults with session_admission:sync."
  end

  desc "Remove reviewed legacy quotas from QUOTA_ALLOWLIST JSON [{namespace, uid}]"
  task remove_legacy_quotas: :environment do
    entries = JSON.parse(File.read(ENV.fetch("QUOTA_ALLOWLIST")))
    raise ArgumentError, "Allowlist must be an array" unless entries.is_a?(Array)
    runtime = ContainerRuntime.build
    raise "Kubernetes runtime required" unless runtime.is_a?(ContainerRuntime::KubernetesRuntime)
    entries.each do |entry|
      runtime.remove_managed_session_quota(namespace: entry.fetch("namespace"), uid: entry.fetch("uid"))
      puts "Requested deletion of reviewed quota in #{entry.fetch('namespace')}"
    end
  end

  desc "Synchronize deployment concurrency settings (requires drained legacy sessions/runs)"
  task sync: :environment do
    unless SessionAdmissionPolicy.current.enabled?
      resources = ContainerRuntime.build.list_session_resources(strict: true)
      raise "Legacy runtime resources remain; drain and clean them before enabling admission" if resources.any?
    end
    policy = SessionAdmissionPolicy.sync!(
      project_default: ENV.fetch("SESSION_PROJECT_CONCURRENCY_DEFAULT", "2"),
      user_default: ENV.fetch("SESSION_USER_CONCURRENCY_DEFAULT", "2")
    )
    puts "Session admission enabled: installation_limit=#{policy.installation_limit || 'scoped'}, revision=#{policy.revision}"
  end

  desc "Pause new admissions; running sessions keep their slots"
  task pause: :environment do
    SessionAdmissionService.transaction { |policy| policy.update!(paused: true) }
  end

  desc "Display queue and retained reservations without runtime mutations"
  task status: :environment do
    puts "enabled=#{SessionAdmissionPolicy.current.enabled?} paused=#{SessionAdmissionPolicy.current.paused?}"
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
    args.scope_type.constantize.find(id)
    maximum = SessionAdmissionPolicy.positive_integer!(args.max_sessions)
    SessionAdmissionService.transaction do
      limit = SessionConcurrencyLimit.find_or_initialize_by(scope_type: args.scope_type, scope_id: id)
      limit.update!(max_sessions: maximum)
    end
  end
end
