# frozen_string_literal: true

module Api
  module V1
    module Company
      class FoldersPolicy < Api::V1::ApplicationPolicy
        def create? = !read_only?
        def relocate? = !read_only?
        def destroy? = !read_only?
      end
    end
  end
end
