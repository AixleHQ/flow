# frozen_string_literal: true

require "test_helper"

# docs/architecture/temporal-error-handling.md's decision table, as code.
class ContainerService::ErrorClassificationTest < ActiveSupport::TestCase
  def classify(error) = ContainerService::ErrorClassification.classify(error)

  test "network failures and a runtime API having a moment are transient" do
    [ Errno::ECONNREFUSED.new, Errno::ECONNRESET.new, Net::ReadTimeout.new, SocketError.new("dns"),
      Kubeclient::HttpError.new(503, "unavailable", nil), Kubeclient::HttpError.new(429, "slow down", nil),
      Kubeclient::HttpError.new(0, "connection reset", nil),
      Docker::Error::ServerError.new("500"), Docker::Error::TimeoutError.new("timed out") ].each do |error|
      assert_equal :transient, classify(error), error.class.name
    end
  end

  test "a missing object is gone" do
    assert_equal :gone, classify(Kubeclient::ResourceNotFoundError.new(404, "pods 'x' not found", nil))
    assert_equal :gone, classify(Docker::Error::NotFoundError.new("no such container"))
  end

  test "everything else is fatal" do
    [ Kubeclient::HttpError.new(403, "forbidden", nil), Kubeclient::HttpError.new(422, "invalid", nil),
      RuntimeError.new("ports not ready"), ArgumentError.new("bad input") ].each do |error|
      assert_equal :fatal, classify(error), error.class.name
    end
  end
end
