# frozen_string_literal: true

# Points an agent container at an address it can actually reach.
#
# On the Docker runtime the application serves its own files, and the URL it
# writes carries the address a browser uses. Inside the container network that
# resolves to nothing, so the host is replaced with one the container can reach
# (`CONTAINER_ASSET_HOST`, `web:4000` by default).
#
# NEVER A SIGNED URL. With S3 storage the URL is presigned by AWS, its signature
# covers the host, and it is already reachable from anywhere. Moving the host
# there produces a link that looks right and answers 403 SignatureDoesNotMatch.
# Where the link is handed to an agent that reads as a broken tool; where it is
# fetched by the application it is a line in a log nobody is watching.
#
# Seen on 30 September 2026 in a Marketplace installation, whose
# CONTAINER_ASSET_HOST named the regional S3 endpoint while the signature had
# been made for the global one. It was found because an agent tried the URL,
# failed, worked out why and said so, which is not a thing to rely on.
#
# This existed as three copies of the same method, in ToolResultResource,
# SessionContextService and WorkflowStepStrategy, which is why one fix would
# have left two.
module ContainerAssetUrl
  SIGNED = /[?&]X-Amz-Signature=/i

  def self.call(url, host:)
    return url if url.blank? || host.blank? || url.match?(SIGNED)

    override = URI.parse(host.start_with?("http") ? host : "http://#{host}")
    uri = URI.parse(url)
    uri.scheme = override.scheme
    uri.host = override.host
    uri.port = override.port
    uri.to_s
  rescue URI::InvalidURIError
    url
  end
end
