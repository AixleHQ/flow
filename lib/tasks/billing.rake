# frozen_string_literal: true

namespace :billing do
  desc "Read every paying company's subscription period back from Stripe"
  task sync_subscriptions: :environment do
    Billing::SubscriptionSync.new.call.each do |company_id, outcome|
      puts "company #{company_id}: #{outcome}"
    end
  end
end
