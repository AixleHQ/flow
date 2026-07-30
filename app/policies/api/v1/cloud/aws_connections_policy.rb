# frozen_string_literal: true

module Api
  module V1
    module Cloud
      # A cloud connection is always the acting user's own, in the company they are
      # acting for, so there is no record to scope against — the only gate is the
      # read-only (viewer) predicate. Viewers must not bind an AWS account.
      class AwsConnectionsPolicy < Api::V1::ApplicationPolicy
        def show? = true # reading one's own connection state is a read
        def create? = !read_only?
        def poll? = !read_only?
        def complete? = !read_only?
        def destroy? = !read_only?
        # A probe spends a token and vends credentials, so it is not a read.
        def health? = !read_only?
      end
    end
  end
end
