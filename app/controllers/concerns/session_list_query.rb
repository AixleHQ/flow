# frozen_string_literal: true

# The ransack `q` a session/run list honours: a date range over created_at and
# a sort (SessionListSort). Anything else in `q` is dropped here, before ransack.
module SessionListQuery
  extend ActiveSupport::Concern

  private

  def list_query
    q = params[:q]
    return {} unless q.respond_to?(:permit)

    q.permit(:s, :created_from, :created_until).to_h.compact_blank
  end
end
