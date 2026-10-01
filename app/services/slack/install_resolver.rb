# frozen_string_literal: true

module Slack
  # Which of a company's Slack installs a call goes through.
  #
  # A run or event that came from Slack names its workspace (the install id and
  # team id it carries), and only that workspace will do: a channel id means
  # nothing in any other one. Anything else uses an install bound to the
  # project, else the company's earliest-connected install, so connecting a
  # second workspace never moves where an existing workflow posts.
  module InstallResolver
    def self.call(company_id:, project_id: nil, integration_id: nil, team_id: nil)
      return nil if company_id.blank?

      installs = Integration.active.where(provider: :slack, company_id: company_id)

      if integration_id.present? || team_id.present?
        return installs.find_by(id: integration_id) ||
               (installs.find_by("settings->>'team_id' = ?", team_id.to_s) if team_id.present?)
      end

      installs.where(project_id: [ project_id, nil ].uniq)
              .order(Arel.sql("project_id IS NULL"), :id)
              .first
    end
  end
end
