# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsPolicy < Api::V1::ApplicationPolicy
      def show? = true # reading one's own session is a read
      def create? = !read_only?
      def destroy? = !read_only?
      def finish? = !read_only?
    end
  end
end
