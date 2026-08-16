# frozen_string_literal: true

module InternalTools
  # get_config_item — hand this session the value of a config item that was
  # deliberately attached to it.
  #
  # This is the ONLY channel by which an agent session receives a credential.
  # There is no env injection and no secret file: one channel means one thing to
  # reason about, and it is the only one that can write an audit row.
  #
  # Two rules carry the security of the whole feature:
  #
  #   1. The candidate set is `SessionConfigResolver#resolve_config_item_ids` —
  #      what somebody attached to THIS session (directly, or through its
  #      workflow/step). Never the project's items. Resolving against the project
  #      would turn this into a general-purpose decryptor and would erase the
  #      meaning of an attachment.
  #   2. Every value handed out is recorded in `config_item_accesses`, without
  #      the value. Attachment is gated on project access alone, so that table is
  #      the only thing that can later answer who read what.
  #
  # `app` execution mode matters here: an app-mode tool creates no `ToolResult`
  # row (see Tools::CallExecutor.execute), so the value is never persisted by the
  # tool pipeline. It does reach the model's context, and from there the provider
  # request body — which is why Sessions::SecretRedactor scrubs the collected
  # logs. See docs/implementation-artifacts/spec-session-config-item-access.md.
  class GetConfigItem < Base
    # A config item is a credential or a setting, not a payload. Anything past
    # this is a misuse of the store, and blowing up the agent's context with it
    # helps nobody.
    MAX_VALUE_BYTES = 8_192

    SECRET_NOTE = "This is a SECRET. It is visible to anyone who can watch this session's live " \
                  "terminal, and to the cluster's log stack if it is printed. Use it in place — do " \
                  "not echo it, do not write it to a file in the workspace, and do not paste it into " \
                  "a commit, an asset or a comment."

    tool do
      display_name "Get Config Item"
      description "Read the value of a secret or environment variable that has been attached to this " \
                  "session (project Secrets & Variables). Call this instead of asking a human to paste " \
                  "a credential, and instead of hardcoding one. Only items attached to this session are " \
                  "readable — the context file lists which, by name. Secrets are returned in plain text: " \
                  "use the value directly in the command or request that needs it, and never print it."
      tags :resources
      inject_when :config_items_attached
      user_attachable false
      read_only true
      destructive false
      idempotent true
      open_world false
      param :name, type: :string, required: true,
                   description: "Name of the config item, e.g. STRIPE_API_KEY. Case-insensitive."
    end

    def execute
      requested = params[:name].to_s.strip.upcase
      return error("Pass the `name` of the config item to read.") if requested.blank?

      item = available_items.find { |ci| ci.name == requested }
      return error(unavailable_message(requested)) if item.nil?

      value = item.decrypted_value
      return error(undecryptable_message(item)) if value.nil?
      return error(oversized_message(item, value)) if value.bytesize > MAX_VALUE_BYTES

      # Written BEFORE the value leaves the process: a crash between the two
      # should leave an over-reported audit trail, never an under-reported one.
      ConfigItemAccess.record!(config_item: item, session: session, user: session.user)

      success(payload(item, value).to_json)
    end

    private

    # The attached set, resolved through the same cascade the session was
    # configured with. `where(id:)` on top of it so a stale id (item deleted
    # after attachment) simply disappears.
    def available_items
      @available_items ||= begin
        ids = SessionConfigResolver.new(session).resolve_config_item_ids
        ids.present? ? ConfigItem.where(id: ids).to_a : []
      end
    end

    def payload(item, value)
      {
        name: item.name,
        item_type: item.item_type.to_s,
        description: item.description.presence,
        value: value
      }.compact.tap do |h|
        h[:note] = SECRET_NOTE if item.secret?
      end
    end

    # Names are project-public (the picker shows them), so naming what IS
    # available is not a leak — and it is the only way the agent can recover
    # from asking for the wrong one.
    def unavailable_message(requested)
      names = available_items.map(&:name).sort
      "Config item #{requested} is not available to this session. " \
        "Available: #{names.presence&.join(', ') || 'none'}. " \
        "Attach it to the session, the workflow or the step to make it readable."
    end

    # nil comes back from ConfigItem#decrypted_value when the row cannot be
    # decrypted with the current key (a rotation that never got its recrypt).
    # Returning "" here would read as a legitimately empty secret and send the
    # agent off to debug the wrong system.
    def undecryptable_message(item)
      "Config item #{item.name} could not be decrypted — its stored value does not match the " \
        "current encryption key. Re-enter the value in the project's Secrets & Variables page."
    end

    def oversized_message(item, value)
      "Config item #{item.name} is #{value.bytesize} bytes, over the #{MAX_VALUE_BYTES}-byte limit " \
        "for a config item. Store large payloads as an asset, not as a secret."
    end
  end
end
