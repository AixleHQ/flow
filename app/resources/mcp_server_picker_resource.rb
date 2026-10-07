# frozen_string_literal: true

# PickerResource plus what the `@` reference picker shows next to a server's name
# when two read alike: where it comes from and how it is reached.
class MCPServerPickerResource < PickerResource
  typelize %w[http sse stdio]
  attribute :transport do |server|
    server.transport.to_s
  end

  typelize %w[internal project]
  attribute :scope do |server|
    server.scope_indicator
  end
end
