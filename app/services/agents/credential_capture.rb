# frozen_string_literal: true

module Agents
  # Turns the auth files found in a container into the credential hash we persist.
  #
  # Extracted from AgentBaseStrategy so the cleanup path and the live write-back endpoint
  # read a container's credentials the same way — a second implementation would drift, and
  # the two paths must agree on what a credential is.
  #
  # The adapter's #extract_credentials is a clean slice of the keys we keep, so what lands
  # in the database is the token material and not a whole vendor config blob.
  class CredentialCapture
    # @param files [Hash] path => file content, as read from the container
    # @param adapter [Agents::BaseAdapter]
    # @param hostname_resolver [Proc, nil] called only when a file needs the container's
    #   hostname to be read (Gemini derives its decryption key from it). Nil means the
    #   caller cannot supply one, and such a file is skipped rather than guessed at.
    # @param log_prefix [String] what a per-file failure is logged under
    # @return [Hash] the credential data to persist (empty when nothing readable was found)
    def self.from_files(files, adapter:, hostname_resolver: nil, log_prefix: "CredentialCapture")
      config_data = {}

      files.each do |path, content|
        basename = File.basename(path.to_s)

        # Gemini: the API key lives in an encrypted file whose key is derived from the
        # container's hostname — decrypt instead of slicing.
        if basename == "gemini-credentials.json" && adapter.respond_to?(:decrypt_credentials_file)
          next if hostname_resolver.nil?

          api_key = adapter.decrypt_credentials_file(content, hostname_resolver.call)
          config_data["api_key"] = api_key if api_key
          next
        end

        # settings.json carries no secrets we persist (auth method marker only). An adapter
        # may still want the non-secret choices recorded there — Claude Code's Bedrock
        # wizard writes its region and model pins here and nowhere else, and those pins are
        # what keep the next session off Opus-rate billing.
        if basename == "settings.json"
          config_data.merge!(adapter.extract_settings_config(content)) if adapter.respond_to?(:extract_settings_config)
          next
        end

        config_data.merge!(adapter.extract_credentials(content))
      rescue StandardError => e
        Rails.logger.warn("[#{log_prefix}] Failed to process #{path}: #{e.message}")
      end

      config_data
    end
  end
end
