# frozen_string_literal: true

# Wraps a Pagy + collection into a standard { items: [...], meta: {...} } JSON shape.
#
# Usage in controllers:
#   pagy, records = paginate(relation)
#   render json: PaginatedResource.build(pagy, records) { |r| SomeResource.new(r).to_h }
#
class PaginatedResource
  def self.build(pagy, records, &block)
    items = block ? records.map(&block) : records
    {
      items: items,
      meta: {
        page: pagy.page,
        perPage: pagy.limit,
        totalPages: pagy.pages,
        totalCount: pagy.count
      }
    }
  end
end
