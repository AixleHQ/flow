# frozen_string_literal: true

# Points an agent container at an address it can reach.
#
# On the Docker runtime the application serves its own files, and the URL it
# writes carries the address a browser uses, which resolves to nothing inside
# the container network.
#
# NEVER A SIGNED URL. With S3 storage the URL is presigned, its signature covers
# the host, and it is already reachable from anywhere. Replacing the host there
# produces a link that looks right and answers 403 SignatureDoesNotMatch.
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
