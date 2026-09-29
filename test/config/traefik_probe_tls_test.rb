# frozen_string_literal: true

require "test_helper"

class TraefikProbeTlsTest < ActiveSupport::TestCase
  test "the session route probe verifies Traefik's certificate unless a deployment opts out" do
    assert verify_tls_with(nil)
    assert verify_tls_with("true")
    assert_not verify_tls_with("false")
  end

  private

  def verify_tls_with(value)
    saved = ENV.fetch("K8S_TRAEFIK_VERIFY_TLS", nil)
    set_env(value)
    settings = YAML.safe_load(ERB.new(Rails.root.join("config/settings.yml").read).result, aliases: true)
    settings.dig("kubernetes", "traefik_verify_tls")
  ensure
    set_env(saved)
  end

  def set_env(value)
    value.nil? ? ENV.delete("K8S_TRAEFIK_VERIFY_TLS") : ENV["K8S_TRAEFIK_VERIFY_TLS"] = value
  end
end
