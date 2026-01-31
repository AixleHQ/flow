# frozen_string_literal: true

class ProjectContext < BaseContext
  attr_reader :project

  def initialize(user, params, project:)
    super(user, params)
    @project = project
  end
end
