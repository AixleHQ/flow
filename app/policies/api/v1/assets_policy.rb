# frozen_string_literal: true

module Api
  module V1
    # Top-level direct-upload endpoints. Caching an upload is a precursor to a
    # write, so a read-only client must never reach them.
    class AssetsPolicy < Api::V1::ApplicationPolicy
      def presign? = !read_only?
      def upload? = !read_only?
    end
  end
end
