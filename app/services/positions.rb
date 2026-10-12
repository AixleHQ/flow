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

  # Closes the gaps a removed row leaves, keeping the order. Same park-then-settle
  # as reorder!, but as two set-based UPDATEs so the query count stays constant.
  def compact!(scope)
    rows = scope.reorder(:position, :id).pluck(:id, :position)
    return [] if rows.empty?

    ids = rows.map(&:first)
    offset = rows.filter_map(&:last).max.to_i
    model = scope.model
    relation = scope.unscope(:order).where(id: ids)
    cases = ids.each_with_index.map { |id, index| model.sanitize_sql_array([ "WHEN ? THEN ?", id, index + 1 ]) }.join(" ")

    model.transaction do
      relation.update_all([ "position = position + ?", offset ])
      relation.update_all("position = CASE id #{cases} END")
    end
    ids
  end
end
