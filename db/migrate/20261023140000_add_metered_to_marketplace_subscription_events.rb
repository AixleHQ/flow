# frozen_string_literal: true

class AddMeteredToMarketplaceSubscriptionEvents < ActiveRecord::Migration[8.1]
  # What the event sent to AWS, if it sent anything.
  #
  # The hourly meter leaves a ledger row per hour carrying its state, its
  # attempts and its error, which is how a refusal on 23 October was seen and
  # fixed within the hour. The final meter -- the one that runs on
  # deprovisioning, inside the window AWS allows and nowhere else -- left
  # nothing at all, so whether it had worked could only be read off the
  # customer's own bill, hours later.
  def change
    add_column :marketplace_subscription_events, :metered, :string
  end
end
