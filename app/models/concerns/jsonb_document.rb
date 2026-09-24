# frozen_string_literal: true

# Writes to a jsonb column that several writers share without undoing each
# other. terminal_sessions.metadata alone carries a launch marker, a
# dead-container marker, repository paths, failed clones, builder activity and a
# cloud-connect request, set from different processes: reading the document,
# changing one key and writing the whole document back erased whatever another
# writer had stored in between.
module JsonbDocument
  extend ActiveSupport::Concern

  # Sets top-level keys in one UPDATE; every other key stays as the database has
  # it. Skips callbacks and validations, like update_columns.
  def merge_jsonb!(column, pairs)
    update_jsonb_keys(column, pairs, [])
  end

  # Removes top-level keys the same way.
  def remove_jsonb_keys!(column, *keys)
    update_jsonb_keys(column, {}, keys)
  end

  # For a change computed from what is there (append to a list, merge into a
  # map): yields the stored document under a row lock and writes back what the
  # block leaves. With `callbacks: true` it saves through the model, for writes
  # the callbacks must see (a broadcast); the record then must have no other
  # unsaved changes, since it is reloaded.
  def change_jsonb!(column, callbacks: false)
    column = jsonb_column!(column)
    self.class.transaction do
      if callbacks
        lock!
        doc = (self[column] || {}).deep_dup
        yield doc
        update!(column => doc)
      else
        doc = (self.class.lock.where(id: id).pick(column) || {}).deep_dup
        yield doc
        self.class.where(id: id).update_all(column => doc)
        write_jsonb_attribute(column, doc)
      end
    end
    self[column]
  end

  private

  def update_jsonb_keys(column, pairs, keys)
    column = jsonb_column!(column)
    quoted = self.class.connection.quote_column_name(column)
    sql = self.class.sanitize_sql_array([
      "UPDATE #{self.class.quoted_table_name} " \
      "SET #{quoted} = (COALESCE(#{quoted}, '{}'::jsonb) || ?::jsonb) - ?::text[] " \
      "WHERE id = ? RETURNING #{quoted}",
      pairs.to_json, PG::TextEncoder::Array.new.encode(keys.map(&:to_s)), id
    ])
    write_jsonb_attribute(column, self.class.type_for_attribute(column).deserialize(self.class.connection.select_value(sql)))
  end

  def jsonb_column!(column)
    column = column.to_s
    raise ArgumentError, "#{column} is not a jsonb column" unless self.class.columns_hash[column]&.type == :jsonb

    column
  end

  def write_jsonb_attribute(column, value)
    self[column] = value
    clear_attribute_change(column)
    value
  end
end
