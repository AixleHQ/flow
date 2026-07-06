# frozen_string_literal: true

# Shared encryption logic for models that store encrypted data.
# Include and define #encryption_key_setting to return the raw key string.
#
# Key derivation: HKDF-SHA256 (RFC 5869) with a versioned salt so any future
# KDF migration can be identified by changing the salt string.
# Run db/migrate/*_recrypt_encryptable_fields.rb before deploying this change.
module Encryptable
  extend ActiveSupport::Concern

  private

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(derived_encryption_key)
  end

  def derived_encryption_key
    raw = encryption_key_setting.to_s
    raise ArgumentError, "[Encryptable] #{self.class.name} encryption key is not set" if raw.blank?

    OpenSSL::KDF.hkdf(raw, salt: "aixle-encryptable-v2", info: self.class.name, length: 32, hash: "SHA256")
  end

  def encryption_key_setting
    raise NotImplementedError, "#{self.class.name} must define #encryption_key_setting"
  end
end
