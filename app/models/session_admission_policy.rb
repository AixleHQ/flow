# frozen_string_literal: true

class SessionAdmissionPolicy < ApplicationRecord
  # A project is a shared workspace: several people, or one person and a couple
  # of workflow steps running beside them, is the ordinary case. A user pool only
  # ever holds project-less sessions, which in practice means agent logins, and
  # nobody signs into four agents at once.
  SCOPE_DEFAULTS = {
    "Project" => { variable: "SESSION_PROJECT_CONCURRENCY_DEFAULT", fallback: 4 },
    "User" => { variable: "SESSION_USER_CONCURRENCY_DEFAULT", fallback: 2 }
  }.freeze

  def self.current = find_by(id: 1) || create_or_find_by!(id: 1)
  def self.enabled? = current.enabled?

  # The size of a scope queue is plain deployment configuration, read live, so a
  # ConfigMap edit takes effect on the next pod with nothing to remember to run.
  #
  # What stays in the database is what cannot be read per-process: whether
  # admission is on at all, whether it is paused, and which pool mode applies —
  # a mode change re-homes live sessions and has to be gated on a drain, which a
  # value re-read at boot could never enforce.
  #
  # The trade-off of reading live is that a rolling update briefly leaves
  # replicas disagreeing about a scope's size. Bounded by the size of the edit,
  # and it settles as the rollout finishes.
  def self.scope_default(scope_type)
    config = SCOPE_DEFAULTS.fetch(scope_type)
    raw = ENV[config[:variable]].to_s.strip
    return config[:fallback] if raw.empty?
    return raw.to_i if raw.match?(/\A[1-9]\d*\z/)

    # Never raise on the grant path: a typo in a ConfigMap must not wedge every
    # queue in the installation. `session_admission:sync` validates strictly, so
    # the operator sees it at cutover instead.
    Rails.logger.error(
      "[SessionAdmission] #{config[:variable]}=#{raw.inspect} is not a positive integer; " \
      "falling back to #{config[:fallback]}"
    )
    config[:fallback]
  end

  def self.scope_defaults = SCOPE_DEFAULTS.keys.index_with { |type| scope_default(type) }

  # Only the operator writes policy, and only in a maintenance window. Workers
  # never interpret their ENV for anything gated here.
  def self.sync!(installation_limit: ENV["SESSION_CONCURRENCY_LIMIT"], enabled: true, paused: false)
    raw = installation_limit.to_s.strip
    cap = raw.empty? ? nil : positive_integer!(raw)
    current
    transaction do
      policy = lock.find(1)
      mode_changed = policy.installation_limit.present? != cap.present?
      switching = mode_changed || policy.enabled? != enabled
      if switching && (TerminalSession.where(state: %w[not_started running ready finishing]).exists? || WorkflowRun.where(state: %w[pending running paused]).exists?)
        raise ArgumentError, "Pause and drain legacy/active sessions before cutover or changing pool mode"
      end
      if switching && SessionAdmission.where(released_at: nil).exists?
        raise ArgumentError, "Drain all admissions before changing pool mode"
      end
      policy.update!(installation_limit: cap, enabled: enabled, paused: paused, revision: policy.revision + 1)
      policy
    end
  end

  def self.positive_integer!(value)
    raise ArgumentError, "Session concurrency must be a positive integer" unless value.to_s.match?(/\A[1-9]\d*\z/)
    value.to_i
  end
end
