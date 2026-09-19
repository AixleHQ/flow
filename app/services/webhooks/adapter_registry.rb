# frozen_string_literal: true

module Webhooks
  class AdapterRegistry
    def self.for(provider)
      Dir[Rails.root.join("app/services/*/webhook_adapter.rb").to_s].each { |file| require_dependency file }
      ProviderAdapter.descendants.find { |adapter| adapter.provider.to_s == provider.to_s }&.new
    end
  end
end
