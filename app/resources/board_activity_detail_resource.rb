# frozen_string_literal: true

class BoardActivityDetailResource < BoardActivityResource
  typelize_from BoardActivity

  typelize "Array<{ field: string; label: string; before: string | null; after: string | null }>"
  attribute :changes do |activity|
    BoardActivityChanges.new(activity).entries
  end
end
