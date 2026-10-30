# frozen_string_literal: true

require "test_helper"

# What the reader actually does on the wire. The thing a fake cannot catch is
# the deletion rule: a message is removed only once its handler returned, and
# one whose handling raised has to stay on the queue to be redelivered.
class Billing::MarketplaceEventsQueueTest < ActiveSupport::TestCase
  QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/444455556666/aixle-staging-marketplace-events"

  # The queue is in this account, so the pod's own identity reads it and no role
  # is assumed. With nothing in the chain the SDK reaches for the EC2 metadata
  # service, so the chain is given something to find.
  AWS_CHAIN_ENV = { "AWS_ACCESS_KEY_ID" => "AKIAPODIDENTITY", "AWS_SECRET_ACCESS_KEY" => "pod-secret" }.freeze

  setup do
    @restore_env = AWS_CHAIN_ENV.keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    ENV.update(AWS_CHAIN_ENV)

    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(saas: { region: "us-east-1", events_queue_url: QUEUE_URL })
    )
    @queue = Billing::MarketplaceEventsQueue.new
  end

  teardown do
    @restore_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "with no queue configured it reads nothing and calls nobody" do
    Settings.stubs(:aws_marketplace).returns(Hashie::Mash.new(saas: { region: "us-east-1" }))

    assert_not Billing::MarketplaceEventsQueue.new.configured?
    assert_equal 0, Billing::MarketplaceEventsQueue.new.each_message { flunk "should not yield" }
  end

  test "it hands over each body parsed and then deletes it" do
    stub_receive([ message("m-1", { "id" => "ev-1" }), message("m-2", { "id" => "ev-2" }) ])
    deletes = stub_delete

    seen = []
    assert_equal 2, @queue.each_message { |envelope| seen << envelope["id"] }

    assert_equal %w[ev-1 ev-2], seen
    assert_requested deletes, times: 2
  end

  # The rule a fake cannot express: deletion is the acknowledgement, so it must
  # follow the handler rather than the receive. And the one behind it is still
  # handled: a message that cannot be taken is redelivered later, not allowed to
  # hold up everything after it.
  test "a message whose handling raised is left on the queue and the rest are handled" do
    stub_receive([ message("m-1", { "id" => "ev-1" }), message("m-2", { "id" => "ev-2" }) ])
    deletes = stub_delete

    seen = []
    handled = @queue.each_message do |envelope|
      raise "handler blew up" if envelope["id"] == "ev-1"

      seen << envelope["id"]
    end

    assert_equal 1, handled
    assert_equal %w[ev-2], seen
    assert_requested deletes, times: 1
  end

  # A body that is not JSON will not become JSON on redelivery, so it is handed
  # over as an empty envelope and acknowledged rather than looping to the DLQ.
  test "an unparseable body is handed over empty and still acknowledged" do
    stub_receive([ raw_message("m-1", "not json at all") ])
    deletes = stub_delete

    seen = []
    assert_equal 1, @queue.each_message { |envelope| seen << envelope }

    assert_equal [ {} ], seen
    assert_requested deletes
  end

  test "an empty queue stops after one receive" do
    receives = stub_receive([])

    assert_equal 0, @queue.each_message { flunk "nothing to yield" }
    assert_requested receives, times: 1
  end

  test "a refused receive is raised as the adapter's own error" do
    stub_request(:post, QUEUE_URL)
      .with(headers: { "X-Amz-Target" => "AmazonSQS.ReceiveMessage" })
      .to_return(status: 403, body: { "__type" => "AccessDeniedException", "message" => "no" }.to_json,
                 headers: { "Content-Type" => "application/x-amz-json-1.0" })

    assert_raises(Billing::MarketplaceEventsQueue::Error) { @queue.each_message { nil } }
  end

  private

  def message(handle, body) = raw_message(handle, body.to_json)

  def raw_message(handle, body)
    { "MessageId" => handle, "ReceiptHandle" => handle, "Body" => body }
  end

  # Answers the batch once, then nothing, so the drain terminates.
  def stub_receive(messages)
    responses = [
      { body: { "Messages" => messages }.to_json },
      { body: { "Messages" => [] }.to_json }
    ]

    stub_request(:post, QUEUE_URL)
      .with(headers: { "X-Amz-Target" => "AmazonSQS.ReceiveMessage" })
      .to_return(*responses.map { |r| r.merge(status: 200, headers: json_headers) })
  end

  def stub_delete
    stub_request(:post, QUEUE_URL)
      .with(headers: { "X-Amz-Target" => "AmazonSQS.DeleteMessage" })
      .to_return(status: 200, body: "{}", headers: json_headers)
  end

  def json_headers = { "Content-Type" => "application/x-amz-json-1.0" }
end
