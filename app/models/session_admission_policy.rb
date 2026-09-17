# frozen_string_literal: true

class SessionAdmissionPolicy < ApplicationRecord
  # A project is a shared workspace: several people, or one person and a couple
  # of workflow steps running beside them, is the ordinary case.
  #
  # Project is the only scope. A "User" scope used to hold project-less sessions,
  # which in practice meant agent logins; those are exempt from admission now
  # (SessionAdmissionService#enqueue!), so the scope governed nothing.
  SCOPE_DEFAULTS = {
    "Project" => { setting: :project_default, variable: "SESSION_PROJECT_CONCURRENCY_DEFAULT", fallback: 4 }
  }.freeze

  # Deployment inputs come from Settings (`session_admission` in
  # config/settings.yml), which is where every other deployment input in this
  # app lives; the environment is still the source, read at boot. Messages keep
  # naming the ENV variable, because that is what an operator actually edits.
  def self.deployment_setting(key)
    Settings.session_admission&.public_send(key)
  end

  def self.current = find_by(id: 1) || create_or_find_by!(id: 1)

  # Answers the gate every session launch asks, and survives the deploy window
  # where the two cannot be in step.
  #
  # The image tag production runs is mutable, so new code starts serving when
  # the image is PUSHED, not when the deploy job runs — and migrations run just
  # before that job. A pod rescheduled in between (spot, autoscaling) executes
  # new code against the old schema for as long as that gap lasts. On
  # 2026-09-05 that cost five sessions: this gate sits on the container-create
  # path, so a table it could not read failed the launch outright.
  #
  # A missing table is not an ambiguous answer. The queue cannot be on if its
  # policy does not exist yet, so say so and let the legacy path serve. Anything
  # else from the database still raises — this narrows to one question, it does
  # not swallow database errors.
  def self.enabled?
    current.enabled?
  rescue ActiveRecord::StatementInvalid => e
    raise unless undefined_table?(e)

    Rails.logger.warn("[SessionAdmission] policy table is not present yet; treating admission as disabled")
    false
  end

  def self.undefined_table?(error)
    error.cause.class.name == "PG::UndefinedTable"
  end

  # The size of a scope queue is plain deployment configuration, read live, so a
  # ConfigMap edit takes effect on the next pod with nothing to remember to run.
  #
  # What stays in the database is what cannot be read per-process: whether
  # admission is on at all, whether it is paused, and the installation ceiling —
  # turning admission on puts already-running sessions behind a queue they were
  # never admitted to, which a value re-read at boot could never gate on.
  #
  # The trade-off of reading live is that a rolling update briefly leaves
  # replicas disagreeing about a scope's size. Bounded by the size of the edit,
  # and it settles as the rollout finishes.
  # The ceiling, read live from the deployment exactly like the project default.
  #
  # It used to be copied into this row by a rake task, because it selected which
  # pool a session belonged to and re-homing live sessions had to happen in a
  # maintenance window. It selects nothing now — it is a number the drain clamps
  # against — so the copy bought only a step that a deployed installation, with
  # no shell, could not perform.
  #
  # THE COST OF READING LIVE: there is no stored value to fall back to, so a
  # ConfigMap typo cannot be "ignored in favour of the last good one" the way the
  # project default can. Refusing to answer would wedge every launch, and
  # guessing a number would be worse — so the ceiling reads as absent and says so
  # loudly, and QueueHealthCheck reports it as a problem rather than leaving it in
  # a log nobody greps.
  def self.installation_limit
    raw = deployment_setting(:installation_limit).to_s.strip
    return nil if raw.empty?
    return raw.to_i if raw.match?(/\A[1-9]\d*\z/)

    Rails.logger.error(
      "[SessionAdmission] SESSION_CONCURRENCY_LIMIT=#{raw.inspect} is not a positive integer; " \
      "the installation has NO ceiling until this is corrected"
    )
    nil
  end

  def self.installation_limit_misconfigured?
    raw = deployment_setting(:installation_limit).to_s.strip
    raw.present? && !raw.match?(/\A[1-9]\d*\z/)
  end

  # Callers hold a policy record and ask it, which kept reading naturally when the
  # value lived in a column; it is the deployment's answer either way.
  def installation_limit = self.class.installation_limit

  def self.scope_default(scope_type)
    config = SCOPE_DEFAULTS.fetch(scope_type)
    raw = deployment_setting(config[:setting]).to_s.strip
    return config[:fallback] if raw.empty?
    return raw.to_i if raw.match?(/\A[1-9]\d*\z/)

    # Never raise on the grant path: a typo in a ConfigMap must not wedge every
    # queue in the installation. QueueHealthCheck reports it instead, so the
    # operator sees it without anything having to raise.
    Rails.logger.error(
      "[SessionAdmission] #{config[:variable]}=#{raw.inspect} is not a positive integer; " \
      "falling back to #{config[:fallback]}"
    )
    config[:fallback]
  end

  def self.scope_defaults = SCOPE_DEFAULTS.keys.index_with { |type| scope_default(type) }

  # Only the operator writes policy, and only in a maintenance window. Workers
  # never interpret their ENV for anything gated here.
  # The cutover, and nothing else. The ceiling is read live now, so there is no
  # deployment value left for this to copy anywhere — only the decision to put
  # new sessions behind a queue, which is not something a config file should be
  # able to make on its own.
  def self.sync!(enabled: true, paused: false)
    current
    transaction do
      policy = lock.find(1)
      # Only turning admission on or off is a cutover now. The installation limit
      # used to select which pool a session belonged to, so changing it re-homed
      # live sessions and had to be drained first; it is a ceiling over the same
      # project pools today, and a ceiling can be moved while they run.
      switching = policy.enabled? != enabled
      if switching && (TerminalSession.where(state: %w[not_started running ready finishing]).exists? || WorkflowRun.where(state: %w[pending running paused]).exists?)
        raise ArgumentError, "Pause and drain legacy/active sessions before cutover"
      end
      if switching && SessionAdmission.where(released_at: nil).exists?
        raise ArgumentError, "Drain all admissions before cutover"
      end
      policy.update!(enabled: enabled, paused: paused, revision: policy.revision + 1)
      policy
    end
  end

  def self.positive_integer!(value)
    raise ArgumentError, "Session concurrency must be a positive integer" unless value.to_s.match?(/\A[1-9]\d*\z/)
    value.to_i
  end
end
