# frozen_string_literal: true

require "pagy/extras/overflow"

module PaginationConcern
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  included do
    include Pagy::Backend
  end

  def per_page
    per = params[:per_page] || DEFAULT_PER_PAGE
    [ per.to_i, MAX_PER_PAGE ].min
  end

  def paginate(relation)
    pagy(relation, limit: per_page)
  end

  def paginated_response(resource, options = {})
    pagy, collection = resource
    serialized_items = if options[:each_serializer] || ActiveModel::Serializer.serializer_for(collection.first)
      ActiveModel::Serializer::CollectionSerializer.new(collection, options).as_json
    else
      collection
    end
    { meta: build_meta(pagy), items: serialized_items }
  end

  def paginated_resource?(resource)
    return false unless resource.is_a?(Array)
    page_object, _ = resource
    page_object.is_a?(Pagy)
  end

  def build_meta(pagy)
    {
      page: pagy.page,
      per_page: pagy.limit,
      total_pages: pagy.pages,
      total_count: pagy.count
    }
  end
end
