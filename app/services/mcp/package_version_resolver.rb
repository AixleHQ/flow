# frozen_string_literal: true

require "net/http"
require "json"

module MCP
  # The release a catalog install pins to when the registry entry names none
  # ("latest" occurs in real payloads). MCPServer refuses an unpinned package line,
  # because the runner would otherwise install whatever was published last at every
  # session start; pinning to the release that is current at install time keeps the
  # connector installable and makes an upgrade something a person does
  # (ConnectorUpdater), not something a publisher does.
  class PackageVersionResolver
    TIMEOUT = 5
    NPM_NAME = %r{\A(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*\z}
    PYPI_NAME = /\A[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?\z/

    class << self
      # The target with its version pinned when it needed one and a registry
      # answered; otherwise the target unchanged.
      def pin(target)
        return target unless target["kind"] == "package" && target["version_pinned"] == false

        version = latest(target["registry_type"], target["identifier"])
        version ? target.merge("version" => version, "version_pinned" => true) : target
      end

      def latest(registry_type, identifier)
        case registry_type.to_s
        when "npm" then npm_latest(identifier.to_s)
        when "pypi" then pypi_latest(identifier.to_s)
        end
      rescue StandardError => e
        Rails.logger.warn("[PackageVersionResolver] #{registry_type} #{identifier}: #{e.class}: #{e.message}")
        nil
      end

      private

      def npm_latest(name)
        return nil unless name.match?(NPM_NAME)

        exact(fetch_json("https://registry.npmjs.org/#{name.sub('/', '%2F')}/latest")&.dig("version"))
      end

      def pypi_latest(name)
        return nil unless name.match?(PYPI_NAME)

        exact(fetch_json("https://pypi.org/pypi/#{name}/json")&.dig("info", "version"))
      end

      def exact(version)
        version.to_s.match?(MCPServer::EXACT_VERSION) ? version.to_s : nil
      end

      def fetch_json(url)
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.get(uri.request_uri, "Accept" => "application/json")
        end
        response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
      end
    end
  end
end
