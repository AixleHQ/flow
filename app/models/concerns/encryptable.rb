# frozen_string_literal: true

# Shared encryption logic for models that store encrypted data.
# Include and define #encryption_key_setting to return the raw key string.
module Encryptable
  extend ActiveSupport::Concern

  private

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(derived_encryption_key)
  end

  def derived_encryption_key
    raw = encryption_key_setting.to_s
    if raw.bytesize < 32
      Rails.logger.warn("[Encryptable] #{self.class.name} encryption key is shorter than 32 bytes — padded with zeros")
    end
    raw.ljust(32, "0")[0..31]
  end

  def encryption_key_setting
    raise NotImplementedError, "#{self.class.name} must define #encryption_key_setting"
  end
end
