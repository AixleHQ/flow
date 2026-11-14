# frozen_string_literal: true

module Runners
  # "Add machine" on a `manual` runner's page (docs/design/agent-runtimes/DESIGN.md
  # §6.3): a single-use registration token and what the operator's copy-paste
  # sequence needs around it, the recommended runner version and, for each
  # platform, the URL of its binary on this platform's own host and its SHA-256
  # from the pins (Runners::Release, §14.3).
  #
  #   registration = Runners::MachineRegistration.issue!(runner, gateway_url: "https://flow.example.com")
  #   registration.token        # shown once; only its digest is stored
  #   registration.binaries     # => [Binary, ...], one per pinned platform
  #
  # It takes the platform's URL and the user as parameters, never the request. A runner that
  # is revoked or deleted is refused with `runner_revoked` by the token's own
  # issuer (Credentials.mint_registration!), under the runner's lock.
  module MachineRegistration
    # One platform's binary: where the platform serves it and its digest.
    Binary = Data.define(:platform, :url, :sha256)
    Registration = Data.define(:token, :expires_at, :gateway_url, :version, :binaries)

    module_function

    def issue!(runner, gateway_url:, created_by: nil)
      raise Credentials::Refused.new("runner_not_manual", "Only a manual runner registers machines.") unless runner.manual?

      version = Release.pins.recommended_version&.to_s
      binaries = version ? binaries_for(version, gateway_url) : []
      if binaries.empty?
        raise Credentials::Refused.new("no_runner_release", "The platform recommends no runner version to install.")
      end

      token = Credentials.mint_registration!(runner, created_by: created_by)
      Registration.new(token: token, expires_at: RunnerCredential.find_by_token(token, kind: :registration).expires_at,
                       gateway_url: gateway_url, version: version, binaries: binaries)
    end

    # The binaries the platform serves for `version`, from its own release
    # endpoint (GET /runner/v1/releases/:version/:platform), which redirects to
    # the release asset.
    def binaries_for(version, gateway_url)
      Release::PLATFORMS.filter_map do |platform|
        pinned = Release.binary(version, platform)
        pinned && Binary.new(platform: platform, sha256: pinned.sha256,
                             url: "#{gateway_url}/runner/v1/releases/#{ERB::Util.url_encode(version)}/#{platform}")
      end
    end
  end
end
