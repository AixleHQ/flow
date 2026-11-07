# frozen_string_literal: true

require "net/http"

module Runners
  # The agent image a runner pulls, pinned by digest (PROTOCOL.md §6.1): the
  # host runner works on `<image>@<digest>` only, so the tag the strategy
  # resolves (`ghcr.io/aixlehq/flow-claude-code:latest`) is looked up in its
  # registry once, through the registry's distribution API, and the answer is
  # cached for CACHE_TTL. A reference already pinned (`…@sha256:…`, through
  # `agents.images.<runtime>`) is used as it is, and asks nothing.
  #
  #   Runners::ImagePin.new.call("ghcr.io/aixlehq/flow-claude-code:latest")
  #   # => { "image" => "ghcr.io/aixlehq/flow-claude-code", "digest" => "sha256:…" }
  #
  # Anonymous pull access is what a public image needs, and what the stock
  # images have. An image the platform cannot resolve fails the pull phase with
  # the registry's answer.
  class ImagePin
    class Error < StandardError; end

    DIGEST = /\Asha256:\h{64}\z/
    DEFAULT_REGISTRY = "registry-1.docker.io"
    # Docker Hub's names: `docker.io/<name>` is served by DEFAULT_REGISTRY, and
    # a name without a namespace is under `library/`.
    DOCKER_HUB = %w[docker.io index.docker.io].freeze
    ACCEPT = [
      "application/vnd.oci.image.index.v1+json",
      "application/vnd.docker.distribution.manifest.list.v2+json",
      "application/vnd.oci.image.manifest.v1+json",
      "application/vnd.docker.distribution.manifest.v2+json"
    ].join(", ").freeze
    CACHE_TTL = 10.minutes
    TIMEOUT = 10

    def call(reference)
      name, digest = reference.to_s.strip.split("@", 2)
      raise Error, "the image reference is blank" if name.blank?

      repository, tag = split_tag(name)
      return pinned(repository, digest) if digest

      digest = Rails.cache.fetch([ "runners/image_pin", repository, tag ], expires_in: CACHE_TTL) do
        resolve(repository, tag)
      end
      pinned(repository, digest)
    end

    private

    def pinned(repository, digest)
      raise Error, "#{digest.inspect} is not a sha256 digest" unless digest.to_s.match?(DIGEST)

      { "image" => repository, "digest" => digest }
    end

    # `host:5000/team/app:1.2` → ["host:5000/team/app", "1.2"]: a colon after
    # the last slash starts the tag, one before it is a registry port.
    def split_tag(name)
      slash = name.rindex("/") || -1
      colon = name.rindex(":")
      return [ name, "latest" ] if colon.nil? || colon < slash

      [ name[0...colon], name[(colon + 1)..] ]
    end

    def resolve(repository, tag)
      host, path = locate(repository)
      uri = URI("https://#{host}/v2/#{path}/manifests/#{tag}")
      response = head(uri)
      if response.is_a?(Net::HTTPUnauthorized)
        token = bearer_token(response["WWW-Authenticate"])
        response = head(uri, token: token) if token
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "the registry #{host} answered #{response.code} for #{repository}:#{tag}"
      end

      digest = response["Docker-Content-Digest"].to_s
      raise Error, "the registry #{host} named no sha256 digest for #{repository}:#{tag}" unless digest.match?(DIGEST)

      digest
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Error, "the registry #{host} could not be reached for #{repository}:#{tag}: #{e.message}"
    end

    def locate(repository)
      first, rest = repository.split("/", 2)
      registry = rest && (first.include?(".") || first.include?(":") || first == "localhost")
      return [ first, rest ] if registry && !DOCKER_HUB.include?(first)

      path = registry ? rest : repository
      [ DEFAULT_REGISTRY, path.include?("/") ? path : "library/#{path}" ]
    end

    # The token endpoint a registry names in its `WWW-Authenticate: Bearer
    # realm=…,service=…,scope=…` challenge, asked anonymously.
    def bearer_token(challenge)
      return nil unless challenge.to_s.start_with?("Bearer ")

      params = challenge.delete_prefix("Bearer ").scan(/(\w+)="([^"]*)"/).to_h
      realm = URI(params.fetch("realm") { return nil })
      realm.query = URI.encode_www_form(params.slice("service", "scope"))
      response = http(realm) { |http| http.request(Net::HTTP::Get.new(realm)) }
      return nil unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body["token"].presence || body["access_token"].presence
    rescue JSON::ParserError, URI::InvalidURIError
      nil
    end

    def head(uri, token: nil)
      request = Net::HTTP::Head.new(uri)
      request["Accept"] = ACCEPT
      request["Authorization"] = "Bearer #{token}" if token
      http(uri) { |http| http.request(request) }
    end

    def http(uri, &)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT,
                                          read_timeout: TIMEOUT, &)
    end
  end
end
