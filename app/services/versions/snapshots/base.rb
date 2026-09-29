# frozen_string_literal: true

module Versions
  module Snapshots
    # A flat snapshot: a fixed list of columns. Every column of the table is
    # either in FIELDS or in EXCLUDED — Versions::SnapshotCompletenessTest fails
    # on a column that is neither, so a new column cannot silently fall out of
    # history (or, worse, a new secret column silently fall into it).
    class Base
      FORMAT = 1

      class << self
        def format = self::FORMAT

        def dump(record)
          record.attributes.slice(*self::FIELDS)
        end

        # Through the model — validations and callbacks on — so derived state
        # (a tool's definition digest, an MCP server's secret reset) stays true.
        def restore!(record, snapshot)
          record.assign_attributes(snapshot.slice(*self::FIELDS))
          record.save!
        end
      end
    end
  end
end
