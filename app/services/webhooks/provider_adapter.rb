# frozen_string_literal: true

module Webhooks
  class ProviderAdapter
    class << self
      attr_accessor :provider
    end

    def verification_strategy = raise NotImplementedError
    def classify(_payload) = raise NotImplementedError
    def redact(_payload, _event_type, _integration) = raise NotImplementedError
    def dedup_key(_endpoint, _event_type, _redacted) = raise NotImplementedError
    def normalize(_received) = raise NotImplementedError
    def run_context(_event, _subject) = raise NotImplementedError
    def requires_integration? = true
    def find_subject(_binding, _event) = nil
    def record_subject!(_task, _binding, _event); end
  end
end
