# frozen_string_literal: true

# The answer to "Add machine" (Runners::MachineRegistration::Registration): a
# registration token, returned once, and what the install instructions are
# written from. Never rendered into Inertia props or any page that can be
# reloaded: the token exists only in the response that issues it.
class RunnerRegistrationResource < ApplicationResource
  typelize :string
  attributes :token

  typelize :string
  attributes :gateway_url

  typelize :string
  attributes :version

  typelize :string
  attribute :expires_at do |registration|
    registration.expires_at.iso8601
  end

  typelize "Array<{ platform: string; url: string; sha256: string }>"
  attribute :binaries do |registration|
    registration.binaries.map { |binary| { platform: binary.platform, url: binary.url, sha256: binary.sha256 } }
  end
end
