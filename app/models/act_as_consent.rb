# frozen_string_literal: true

# What a user allows agents to do with their connected account in one project
# (docs/design/github-user-identity.md §3.1). Two independent switches: acting as
# them in sessions they own, and handing their token out in sessions they don't.
# A missing row means both are off.
class ActAsConsent < ApplicationRecord
  extend Enumerize

  SCOPES = { own: :in_own_tasks, others: :in_others_tasks }.freeze

  belongs_to :user
  belongs_to :project
  belongs_to :company

  enumerize :provider, in: %w[github gitlab]

  validates :provider, presence: true
  validates :project_id, uniqueness: { scope: %i[user_id provider] }
  validate :company_matches_project

  def self.allows?(user:, project:, provider:, scope:)
    column = SCOPES.fetch(scope.to_sym)
    where(user_id: user.id, project_id: project.id, provider: provider.to_s).where(column => true).exists?
  end

  private

  def company_matches_project
    errors.add(:company, "must be the project's company") if project && company_id != project.company_id
  end
end
