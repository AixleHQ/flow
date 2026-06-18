# frozen_string_literal: true

module PaginationConcern
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  included do
    # Pagy 43 renamed the controller mixin Pagy::Backend -> Pagy::Method and
    # folded the old `pagy/extras/overflow` behaviour (empty page on overflow)
    # into the core as the default (it only raises with `raise_range_error: true`).
    include Pagy::Method
  end

  # JSON API pagination: returns [pagy, records]
  def paginate(relation, limit: per_page)
    pagy(relation, limit: limit)
  end

  # Inertia infinite scroll: returns an InertiaRails.scroll prop.
  # Reads params[:per_page] automatically; override with limit: kwarg.
  def inertia_scroll(scope, limit: per_page, &block)
    pagy_obj, records = pagy(scope, limit: limit)
    InertiaRails.scroll(pagy_obj) { block ? block.call(records) : records }
  end

  def per_page
    per = (params[:per_page] || DEFAULT_PER_PAGE).to_i
    per.clamp(1, MAX_PER_PAGE)
  end
end
