# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SkillsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_writable?
        # Authoring a skill by hand is the same authority as installing one: both
        # put instructions into every session this project runs.
        def manual? = project_writable?
        # Editing rewrites those instructions, so it is the same authority again.
        def update? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
