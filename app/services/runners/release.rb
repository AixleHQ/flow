# frozen_string_literal: true

module Runners
  # The platform's runner pins, config/runner_release.yml read as
  # Settings.runners.release (docs/design/agent-runtimes/DESIGN.md §14.2, §14.4):
  # which protocol versions the gateway accepts, the lowest runner version it
  # registers, the version it recommends, and the SHA-256 of every binary it
  # serves. Changing any of them is an application PR to that file.
  #
  #   Runners::Release.protocol_supported?("1")             # X-Aixle-Runner-Protocol
  #   Runners::Release.unsupported_version?("0.0.9")        # below min_version: register refuses it
  #   Runners::Release.binary("0.1.0", "linux-amd64")       # => Binary, or nil when not pinned
  #   Runners::Release.update_for(environment, runner_version: "0.1.0") # => Offer, or nil
  #
  # The pins are read on every call, so a test that stubs Settings sees its own,
  # and checked each time: an invalid file fails boot
  # (config/initializers/runner_release.rb), never a request.
  module Release
    # The runner protocol versions this gateway's code implements. The pins may
    # list only these.
    IMPLEMENTED_PROTOCOLS = [ 1 ].freeze
    # The `<os>-<arch>` of the binaries `runner-release.yml` builds.
    PLATFORMS = %w[linux-amd64 linux-arm64].freeze
    SHA256 = /\A\h{64}\z/

    class InvalidPins < StandardError; end

    Pins = Data.define(:protocol_supported, :min_version, :recommended_version, :download_url, :binaries)
    # One pinned binary: the URL of its release asset and its digest.
    Binary = Data.define(:version, :platform, :url, :sha256)
    # The update an idle machine below the recommended version is offered.
    Offer = Data.define(:version, :platform, :sha256)
    # Every pinned digest of one version, by platform.
    Checksums = Data.define(:version, :binaries)

    module_function

    def pins
      parse(Settings.runners.release.to_h.deep_stringify_keys)
    end

    def protocol_supported?(header)
      header.to_s.match?(/\A[1-9]\d*\z/) && pins.protocol_supported.include?(header.to_i)
    end

    def protocol_supported
      pins.protocol_supported
    end

    # Whether `runner_version` is below min_version. A value that is not a
    # semantic version is refused before it gets here (PROTOCOL.md §1).
    def unsupported_version?(runner_version)
      minimum = pins.min_version
      version = Version.parse(runner_version)
      minimum.present? && version.present? && version < minimum
    end

    def min_version
      pins.min_version
    end

    def binary(version, platform)
      current = pins
      digest = current.binaries.dig(version.to_s, platform.to_s)
      return nil if digest.nil?

      Binary.new(version: version.to_s, platform: platform.to_s, sha256: digest,
                 url: format(current.download_url, version: version, platform: platform))
    end

    # Every pinned digest of `version`, or nil when none is.
    def checksums(version)
      binaries = pins.binaries[version.to_s]
      binaries && Checksums.new(version: version.to_s, binaries: binaries)
    end

    # The update `environment` is offered by the answer of its long-poll that
    # has no ops (PROTOCOL.md §5.4, decision 2 of task #217), or nil: only while
    # the machine is registered and holds no session, only towards
    # recommended_version, only when the binary for its os and arch is pinned,
    # and never when its runner (`config.auto_update`) or the machine itself
    # (`configure --no-auto-update`) opted out. `runner_version` is the version
    # the request reports, which a machine that updated itself has moved on from
    # the one it registered with.
    def update_for(environment, runner_version:)
      current = pins
      recommended = current.recommended_version
      version = Version.parse(runner_version)
      return nil if recommended.nil? || version.nil? || version >= recommended
      return nil unless environment.state == "registered" && environment.current_session_id.nil?
      return nil unless environment.auto_update && ConfigSchema.value(environment.runner.config, "auto_update") != false

      platform = "#{environment.os}-#{environment.arch}"
      digest = current.binaries.dig(recommended.to_s, platform)
      digest && Offer.new(version: recommended.to_s, platform: platform, sha256: digest)
    end

    # == validation ==

    KEYS = %w[protocol_supported min_version recommended_version download_url binaries].freeze

    def parse(raw)
      unknown = raw.keys - KEYS
      invalid!("unknown keys #{unknown.join(', ')}") if unknown.any?

      min = version_or_nil(raw["min_version"], "min_version")
      recommended = version_or_nil(raw["recommended_version"], "recommended_version")
      invalid!("recommended_version #{recommended} is below min_version #{min}") if min && recommended && recommended < min

      binaries = parse_binaries(raw["binaries"])
      if recommended && binaries[recommended.to_s].blank?
        invalid!("recommended_version #{recommended} has no pinned binaries")
      end

      Pins.new(protocol_supported: parse_protocols(raw["protocol_supported"]), min_version: min,
               recommended_version: recommended, download_url: parse_download_url(raw["download_url"]),
               binaries: binaries)
    end

    def parse_protocols(value)
      unless value.is_a?(Array) && value.any? && value.all?(Integer)
        invalid!("protocol_supported must be a non-empty list of integers")
      end
      unimplemented = value - IMPLEMENTED_PROTOCOLS
      invalid!("protocol_supported lists #{unimplemented.join(', ')}, which this gateway does not implement") if unimplemented.any?

      value.uniq.freeze
    end

    def version_or_nil(value, key)
      return nil if value.nil?

      Version.parse(value) || invalid!("#{key} #{value.inspect} is not a semantic version")
    end

    def parse_download_url(value)
      valid = value.is_a?(String) && value.include?("%{version}") && value.include?("%{platform}") &&
              value.match?(%r{\Ahttps?://[^/\s]+/\S*\z})
      invalid!("download_url must be an http(s) URL with %{version} and %{platform}") unless valid

      value
    end

    def parse_binaries(value)
      invalid!("binaries must be a map of versions") unless value.is_a?(Hash)

      value.to_h do |version, platforms|
        invalid!("binaries: #{version.inspect} is not a semantic version") unless Version.valid?(version)
        invalid!("binaries.#{version} must be a map of platforms") unless platforms.is_a?(Hash) && platforms.any?

        [ version, platforms.to_h { |platform, pin| [ platform, parse_pin(version, platform, pin) ] }.freeze ]
      end.freeze
    end

    def parse_pin(version, platform, pin)
      invalid!("binaries.#{version}: #{platform.inspect} is not one of #{PLATFORMS.join(', ')}") unless PLATFORMS.include?(platform)
      digest = pin["sha256"] if pin.is_a?(Hash) && pin.keys == [ "sha256" ]
      invalid!("binaries.#{version}.#{platform} must be { sha256: <64 hex digits> }") unless digest.is_a?(String) && digest.match?(SHA256)

      digest.downcase
    end

    def invalid!(message)
      raise InvalidPins, "config/runner_release.yml: #{message}"
    end
  end
end
