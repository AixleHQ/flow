# frozen_string_literal: true

module Sessions
  # Publishes, into the running container, the list of session secrets its log filters
  # must remove.
  #
  # Redaction used to happen only where a log was collected (Sessions::SecretRedactor),
  # which means the bytes have to travel through this application to be cleaned — and
  # that, not storage cost, is why log collection needs a size cap at all. The filters
  # inside the container (docker/base/logger/aixle_redact.py and its JS twin) clean at
  # the point of writing instead; this is what tells them what to look for.
  #
  # The list is derived from `config_item_accesses`, so it holds exactly the values this
  # session has already been handed and nothing else. That is what makes writing it into
  # the container safe: it tells the container nothing the container did not ask for.
  # The file is root-owned so the agent cannot quietly empty it, and world-readable
  # because the pane filter runs as the agent's own user while the proxy runs as root.
  #
  # One base64-encoded value per line: a secret may contain newlines, and base64 keeps
  # one value on one line whatever it holds.
  class SecretRegistry
    LIST_PATH = "/var/log/mitm/redact.list"
    FILE_MODE = 0o644

    def self.publish!(session, runtime: nil)
      new(session, runtime: runtime).publish!
    end

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    # True when the container is carrying a list that covers every secret this session
    # has been handed — including, deliberately, when there is no container: the logs
    # this protects are the ones written inside one.
    def publish!
      return true if session.nil? || session.container_id.blank?

      container_runtime.write_file(
        session.container_id, LIST_PATH, payload,
        mode: FILE_MODE, uid: 0, gid: 0
      )
    rescue StandardError => e
      Rails.logger.warn("[SecretRegistry] session=#{session&.id} could not publish the redaction list: #{e.class}: #{e.message}")
      false
    end

    private

    attr_reader :session, :runtime

    def payload
      values.map { |value| Base64.strict_encode64(value) }.join("\n") + "\n"
    end

    # Every secret handed out so far, not just the one being fetched: the file is
    # rewritten whole, so deriving it from the audit trail makes a republish idempotent
    # and lets it heal a container that missed an earlier write.
    def values
      ConfigItemAccess
        .where(terminal_session_id: session.id, item_type: "secret")
        .includes(:config_item)
        .filter_map { |access| access.config_item&.decrypted_value.presence }
        .uniq
    end

    def container_runtime
      @container_runtime ||= runtime || ContainerRuntime.build
    end
  end
end
