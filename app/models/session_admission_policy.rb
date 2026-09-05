# frozen_string_literal: true

class SessionAdmissionPolicy < ApplicationRecord
  def self.current = find_by(id: 1) || create_or_find_by!(id: 1)
  def self.enabled? = current.enabled?

  # Only the deployment/operator writes policy. Workers never interpret their ENV.
  def self.sync!(installation_limit: ENV["SESSION_CONCURRENCY_LIMIT"], project_default: 2, user_default: 2, enabled: true, paused: false)
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
      policy.update!(installation_limit: cap, project_default: positive_integer!(project_default), user_default: positive_integer!(user_default), enabled: enabled, paused: paused, revision: policy.revision + 1)
      policy
    end
  end

  def self.positive_integer!(value)
    raise ArgumentError, "Session concurrency must be a positive integer" unless value.to_s.match?(/\A[1-9]\d*\z/)
    value.to_i
  end
end
