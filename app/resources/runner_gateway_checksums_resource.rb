# frozen_string_literal: true

# The pinned digests of one runner release as GET
# /runner/v1/releases/:version/checksums returns them (runner/protocol/PROTOCOL.md
# §5.7), from Runners::Release::Checksums. Snake_case like the rest of the runner
# protocol, and not a browser type.
class RunnerGatewayChecksumsResource
  include Alba::Resource

  transform_keys :none

  attributes :version

  attribute :binaries do |checksums|
    checksums.binaries.transform_values { |sha256| { "sha256" => sha256 } }
  end
end
