# frozen_string_literal: true

# Renumbers rows that share a unique (parent, position) index — a workflow's
# steps, a board's columns. The rows named come first, in the order given; every
# other row of the scope follows in its current order, soft-deleted ones
# included, because they still hold a slot in the index. All rows first park
# above the highest position in use and then come down to 1..n, so no write ever
# lands on a slot another row still holds. Renumbering only the named rows is
# what collided: with a row left out, or with a deleted step keeping its number.
module Positions
  module_function

  def reorder!(scope, ordered_ids)
    rows = scope.reorder(:position, :id).to_a
    by_id = rows.index_by(&:id)
    named = Array(ordered_ids).map(&:to_i).uniq.filter_map { |id| by_id[id] }
    final = named + (rows - named)

    scope.model.transaction do
      offset = rows.filter_map(&:position).max.to_i
      final.each_with_index { |row, index| row.update_column(:position, offset + index + 1) }
      final.each_with_index { |row, index| row.update_column(:position, index + 1) }
    end
    final
  end
end
