# frozen_string_literal: true

# Passkeys (CAP-4, AD-18).
#
# The RP ID is the registrable domain WITHOUT a port — a credential is bound to
# it, so getting this wrong does not fail loudly, it silently produces passkeys
# that no other page of the app can use. `allowed_origins` keeps the port,
# because an origin check is exact.
WebAuthn.configure do |config|
  host = Settings.domain.to_s
  config.allowed_origins = [ "#{Settings.protocol}://#{host}" ]
  config.rp_id = host.split(":").first
  config.rp_name = Settings.project_name
  # A passkey is an authentication credential, not a device attestation
  # programme: we do not collect or verify attestation statements, which keeps
  # AAGUID metadata and its maintenance out of this app entirely.
  config.encoding = :base64url
end
