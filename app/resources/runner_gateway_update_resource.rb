# frozen_string_literal: true

# The `update` of an answer of GET /runner/v1/ops without ops
# (runner/protocol/PROTOCOL.md §5.4), from Runners::Release::Offer: the version the
# platform recommends and the binary's pinned SHA-256. It names no URL: the runner
# asks its own configured platform for the release. Snake_case like the rest of the
# runner protocol, and not a browser type.
class RunnerGatewayUpdateResource
  include Alba::Resource

  transform_keys :none

  attributes :version, :sha256
end
