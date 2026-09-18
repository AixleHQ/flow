# frozen_string_literal: true

# When the reconciler first proved the workload behind a pinned reservation is
# gone. The pin (AD-5) exists so a late Pod never lands on a seat handed to
# someone else; this column is what lets that wait end without a human, by
# measuring how long the absence has held UNINTERRUPTED — a pass that sees the
# workload again clears it, so the window can never be assembled from moments.
class AddAbsentSinceToSessionRuntimeOperations < ActiveRecord::Migration[8.1]
  def change
    add_column :session_runtime_operations, :absent_since, :datetime
  end
end
