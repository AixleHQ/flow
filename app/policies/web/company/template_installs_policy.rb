# frozen_string_literal: true

module Web
  module Company
    # Installing a catalog template. Browsing the catalog is public and needs no
    # policy; installing needs a writable seat: a viewer can neither create a
    # project nor add resources to one.
    #
    # With a company context this answers "may install into this company at
    # all" (and so create a new project there); with a project context it
    # answers "may add resources to this project". Changing a project's board
    # additionally needs the project owner — see Projects::BoardsPolicy.
    class TemplateInstallsPolicy < ApplicationPolicy
      def new? = company_writer?
      def create? = company_writer?
      def install_into_project? = project_writable?

      private

      def company_writer?
        membership.present? && !read_only?
      end
    end
  end
end
