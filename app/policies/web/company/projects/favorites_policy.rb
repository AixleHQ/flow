# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Deliberately `project_accessible?` on the writes, not `project_writable?`:
      # a favorite is the actor's own view preference, and it mutates nothing
      # about the project or anyone else's list. A read-only viewer who can see
      # the project can order their own list — the same reason the profile page
      # lets a viewer change their own preferences.
      class FavoritesPolicy < Web::Company::ApplicationPolicy
        def create? = project_accessible?
        def destroy? = project_accessible?
      end
    end
  end
end
