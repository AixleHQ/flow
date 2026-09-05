# frozen_string_literal: true

class SessionConcurrencyLimit < ApplicationRecord
  validates :scope_type, inclusion: { in: %w[Project User] }
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }

  def self.set!(scope:, max_sessions:)
    SessionAdmissionService.transaction do |policy|
      find_or_initialize_by(scope_type: scope.class.base_class.name, scope_id: scope.id).update!(max_sessions: max_sessions)
      policy.update!(revision: policy.revision + 1)
    end
    # Raising a cap that nobody drains is a cap that takes effect a minute late.
    SessionAdmissionService.drain!
  end
end
