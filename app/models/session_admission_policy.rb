# frozen_string_literal: true

class SessionAdmissionPolicy < ApplicationRecord
  # Admission is always on and cannot be paused. The previous image still reads
  # both columns during a rollout (see AlwaysEnableSessionAdmission); they are
  # dropped once none remain.
  self.ignored_columns += %w[enabled paused]

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

  # The size of a scope queue is plain deployment configuration, read live, so a
  # ConfigMap edit takes effect on the next pod with nothing to remember to run.
  #
  # The trade-off of reading live is that a rolling update briefly leaves
  # replicas disagreeing about a scope's size. Bounded by the size of the edit,
  # and it settles as the rollout finishes.
  #
  # THERE IS NO INSTALLATION CEILING ANY MORE. SESSION_CONCURRENCY_LIMIT was one
  # number for a whole deployment, read from the environment, and every project
  # reservation was drawn from it. That cannot express an installation running
  # several organisations, and it is not a number anybody is sold: what a
  # customer buys is capacity for their organisation. The budget is the company's
  # own limit now (SessionConcurrencyAllocation), and nothing reads the variable.

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

  # Whether the reconciler may end a pinned reservation on its own, and how long
  # proven absence has to hold first. Off, a pinned slot waits for a human again.
  def self.pinned_release_enabled? = deployment_setting(:pinned_release_enabled) != false

  def self.pinned_release_window
    minutes = deployment_setting(:pinned_release_confirmation_minutes).to_i
    (minutes.positive? ? minutes : 5).minutes
  end

  def self.positive_integer!(value)
    raise ArgumentError, "Session concurrency must be a positive integer" unless value.to_s.match?(/\A[1-9]\d*\z/)
    value.to_i
  end
end
