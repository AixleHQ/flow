# frozen_string_literal: true

# One catalog entry as the browser sees it.
#
# The manifest is NOT serialized wholesale: the browser needs the installable
# targets and their declared inputs to render an install form, and nothing else.
# Sending the raw normalized manifest would leak registry dialect into the
# frontend and defeat MCP::ConnectorManifest's whole purpose as the single place
# that knows the upstream shape.
class ConnectorResource < ApplicationResource
  attributes :id, :name, :title, :description, :version, :repository_url,
             :registry_updated_at, :created_at, :updated_at

  typelize %w[active deprecated deleted]
  attribute :status do |connector|
    connector.status.to_s
  end

  typelize :boolean
  attribute :installable do |connector|
    connector.installable?
  end

  typelize :string
  attribute :picker_name do |connector|
    connector.picker_name
  end

  # Derived from the registry namespace, never curated. Null when the namespace
  # yields nothing usable; the UI then draws a monogram.
  typelize :string?
  attribute :icon_url do |connector|
    connector.icon_url
  end

  # The registry verified this publisher owns the domain, rather than merely
  # holding a GitHub account.
  typelize :boolean
  attribute :vendor_published do |connector|
    connector.vendor_published?
  end

  # Every target, installable or not. Unsupported ones travel with their reason
  # so the UI can explain why a connector cannot be installed rather than
  # silently showing an entry with no install button.
  typelize targets: "Array<{ id: string; kind: string; transport: string; supported: boolean; " \
                    "unsupported_reason: string | null; url: string | null; registry_type: string | null; " \
                    "identifier: string | null; command: string | null; " \
                    "version: string | null; version_pinned: boolean; runtime: string | null; " \
                    "runtime_prefix_args: string[]; " \
                    "inputs: Array<{ key: string; kind: string; description: string | null; format: string; " \
                    "required: boolean; secret: boolean; default: string | null; choices: string[] | null; " \
                    "placeholder: string | null; repeated: boolean }> }>"
  attribute :targets do |connector|
    Array(connector.manifest["targets"]).map do |target|
      {
        # Stable id the install submits back, so the server resolves the target
        # against a freshly-fetched manifest instead of trusting a client
        # description of it — and so a reordered manifest cannot misdirect it.
        id: target["id"],
        kind: target["kind"],
        transport: target["transport"],
        supported: target["supported"] == true,
        unsupported_reason: target["unsupported_reason"],
        url: target["url"],
        registry_type: target["registry_type"],
        identifier: target["identifier"],
        # The exact launch line, so "runs code in your agent container" can name
        # the code. A security decision made from a vague label is not consent.
        command: launch_command(target),
        version: target["version"],
        version_pinned: target["version_pinned"] != false,
        runtime: target["runtime"],
        runtime_prefix_args: Array(target["runtime_prefix_args"]),
        inputs: Array(target["inputs"]).map { |input| serialize_input(input) }
      }
    end
  end

  # "npx @scope/pkg@1.2.3". Nil for remote targets, which launch nothing.
  def launch_command(target)
    return nil unless target["kind"] == "package" && target["runtime"].present?

    identifier = target["identifier"]
    spec =
      if identifier.blank? || target["version_pinned"] == false
        identifier
      elsif target["registry_type"] == "oci"
        "#{identifier}:#{target['version']}"
      else
        "#{identifier}@#{target['version']}"
      end

    ([ target["runtime"] ] + Array(target["runtime_prefix_args"]) + [ spec ]).compact.join(" ")
  end

  # Instance method: Alba evaluates attribute blocks against the resource.
  def serialize_input(input)
    {
      key: input["key"],
      kind: input["kind"],
      description: input["description"],
      format: input["format"] || "string",
      required: input["required"] == true,
      secret: input["secret"] == true,
      default: input["default"],
      choices: input["choices"],
      placeholder: input["placeholder"],
      repeated: input["repeated"] == true
    }
  end
end
