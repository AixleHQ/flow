# frozen_string_literal: true

class AddReceiptsToCapacityMeterReports < ActiveRecord::Migration[8.1]
  # What the provider gave back per record, keyed by whoever it was for.
  #
  # `external_id` carries our own summary of the hour, which is what we believe
  # happened. This carries what the provider says: AWS answers every accepted
  # usage record with a MeteringRecordId, and until now the adapter read it and
  # threw it away. Without it, "the hour was billed" rests on our own word and
  # the next independent check is the customer's invoice, hours behind.
  def change
    add_column :capacity_meter_reports, :receipts, :jsonb, default: {}, null: false
  end
end
