# frozen_string_literal: true

module Api
  module V1
    module Company
      class AssetsPolicy < Api::V1::ApplicationPolicy
        def download? = true # any authenticated company member may read
        def create? = !read_only?
        def destroy? = !read_only?
      end
    end
  end
end
