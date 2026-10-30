# frozen_string_literal: true

# An op as GET /runner/v1/ops delivers it to `aixle-runner`
# (docs/design/agent-runtimes/DESIGN.md §6.4). Snake_case like the rest of the
# runner protocol, and not a browser type. The payload is decrypted here and
# travels only in this response.
class RunnerGatewayOperationResource
  include Alba::Resource

  transform_keys :none

  attributes :id, :sequence, :op

  attribute :deadline_at do |operation|
    operation.deadline_at.iso8601
  end

  attributes :payload
end
