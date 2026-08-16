# frozen_string_literal: true

module ContextBuilders
  # Tells the agent which secrets and variables it may read, by NAME, and how to
  # read them. No value ever appears here — the context file is written into the
  # container and echoed into `context.log`, and the whole point of routing values
  # through `get_config_item` is that they are fetched on demand and audited.
  #
  # Without this section the tool is effectively invisible: an agent that does not
  # know `STRIPE_API_KEY` exists will ask a human to paste it, which is the
  # behaviour this feature exists to replace.
  class ConfigItems < Base
    def applicable?
      attached_items.any?
    end

    def build
      [ section(tag: "available-config-items", priority: :important, content: content) ]
    end

    private

    def attached_items
      @attached_items ||= begin
        ids = SessionConfigResolver.new(session).resolve_config_item_ids
        ids.present? ? ConfigItem.where(id: ids).order(:name).to_a : []
      end
    end

    def content
      lines = [ "## Secrets & Variables available to this session" ]
      lines << ""
      lines << "Call the `get_config_item` tool with a name below to read its value. " \
               "Never ask a person to paste one of these, and never hardcode a credential " \
               "into a workflow, a commit or a file."
      lines << ""
      lines << "| Name | Type | Description |"
      lines << "|---|---|---|"
      attached_items.each do |item|
        lines << "| `#{item.name}` | #{item.item_type} | #{item.description.presence || '—'} |"
      end

      if attached_items.any?(&:secret?)
        lines << ""
        lines << "Items marked **secret** are credentials. Use the value directly in the command or " \
                 "request that needs it; do not echo it to the terminal, do not write it into a file " \
                 "in the workspace, and do not include it in a commit, an asset or a comment. " \
                 "Anything printed in this session is visible to whoever can watch the session."
      end

      lines.join("\n")
    end
  end
end
