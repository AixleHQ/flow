# frozen_string_literal: true

# The `update` of an answer of GET /runner/v1/ops without ops
# (runner/protocol/PROTOCOL.md §5.4), from Runners::Release::Offer: the version the
# platform recommends, its release URL on the platform, and the binary's pinned
# SHA-256. The controller passes the URL, built from the request's own host, as
# `params[:url]`. Snake_case like the rest of the runner protocol, and not a browser
# type.
class RunnerGatewayUpdateResource
  include Alba::Resource

  transform_keys :none

  attributes :version

  attribute :url do
    params.fetch(:url)
  end

  attributes :sha256
end
