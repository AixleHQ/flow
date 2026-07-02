# frozen_string_literal: true

class ProjectContext < BaseContext
  attr_reader :project

  # The company is derived from the project (NOT from the web session), which
  # keeps API-side authorization company-correct without a session.
  def initialize(user, params, project:)
    super(user, params, company: project&.company)
    @project = project
  end
end
