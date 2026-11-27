# frozen_string_literal: true

module Integrations
  # The integrations a project's workflows had before they were chosen per session, and the ones the
  # new-session form preselects (docs/design/session-integrations.md §5.1, §7): the project's Coder
  # (its own active one, else the company's, the earliest by id), every active Slack and Teams
  # install the project can see (what the chat tools reach), and its Azure DevOps connections.
  # Nothing is returned for a provider the project has no integration of.
  module Defaults
    CHAT_PROVIDERS = %w[slack teams].freeze

    module_function

    # → integration ids. `logger` hears about Coder integrations left out because there are several.
    def ids(project, logger: nil)
      (coder_pick(project, logger) + chat_installs(project) + azure_connections(project)).uniq
    end

    def coder_pick(project, logger)
      active = Integration.active.where(provider: :coder, company_id: project.company_id)
      own = active.where(project_id: project.id).order(:id).to_a
      candidates = own.presence || active.where(project_id: nil).order(:id).to_a
      if logger && candidates.size > 1
        logger.info("[Integrations] project #{project.id} has #{candidates.size} active Coder integrations; " \
                    "chose #{candidates.first.id}, left #{candidates.drop(1).map(&:id).join(', ')}")
      end
      candidates.first(1).map(&:id)
    end

    def chat_installs(project)
      Chat::ChannelAccess.installs(project).where(provider: CHAT_PROVIDERS).order(:id).pluck(:id)
    end

    def azure_connections(project)
      Integration.active.where(provider: :azure_devops, project_id: project.id).order(:id).pluck(:id)
    end
  end
end
