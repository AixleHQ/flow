# frozen_string_literal: true

module IntegrationProviderContracts
  module ConnectService
    def test_connect_service_contract
      integration = connect_service.call(**valid_connection_params)
      assert integration.persisted?
      assert integration.active?
      assert integration.name.present?
      assert integration.settings["error"].blank?
      assert integration.youtrack_webhook_endpoint&.secret.present?
      assert_nil integration.credentials_data["webhook_token"]
    end
  end

  module WebhookAdapter
    def test_webhook_adapter_contract
      assert adapter.class.provider.present?
      assert adapter.verification_strategy.present?
      assert_equal :unsupported, adapter.classify({ "event" => "unknown" })
      event_type = adapter.classify(valid_payload)
      assert_kind_of String, event_type
      redacted = adapter.redact(valid_payload, event_type, integration)
      assert_kind_of Hash, redacted
      assert adapter.dedup_key(endpoint, event_type, redacted).present?
      changed_timestamp = redacted.deep_dup.merge("timestamp" => "later")
      assert_equal adapter.dedup_key(endpoint, event_type, redacted),
        adapter.dedup_key(endpoint, event_type, changed_timestamp)
      received = Struct.new(:webhook_endpoint, :raw_payload).new(endpoint, redacted)
      normalized = adapter.normalize(received)
      assert_equal event_type, normalized[:event_type]
      assert_kind_of Hash, normalized[:data]
    end
  end

  module IntegrationResolvable
    def test_integration_resolvable_contract
      resolved = resolver.youtrack_integration
      assert_equal preferred_integration, resolved
      resolver.workflow_run = Struct.new(:shared_context).new({ "youtrack" => { "integration_id" => "missing" } })
      assert_equal preferred_integration, resolver.youtrack_integration
    end
  end
end
