# frozen_string_literal: true

namespace :platform_tools do
  desc "Reconcile code-defined platform tools into shadow rows (idempotent — safe to re-run)"
  task seed: :environment do
    Tools::Reconciler.run!
    puts "Reconciled #{Tools::Registry.names.size} platform tools." unless Rails.env.test?
  end
end
