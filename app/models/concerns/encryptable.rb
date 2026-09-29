# frozen_string_literal: true

# Shared encryption for models that store secrets.
#
#   include Encryptable
#   encryption_key :credentials_key
#   encrypted_column :encrypted_token
#
# The raw key is Settings.encryption[name], stretched per model with
# HKDF-SHA256 (RFC 5869); the versioned salt marks the KDF generation.
#
# Rotation: put the retired key(s) in Settings.encryption["<name>_previous"]
# (comma-separated). Reads fall back to them, writes always use the current key,
# and `bin/rails encryption:reencrypt` moves every stored secret onto it.
#
# A ciphertext is bound to its model and column (the message purpose), so a
# value copied into another column or another model's row does not decrypt.
# Values written before purposes existed still read, and the re-encrypt task
# binds them. New values are bound only once `encryption.bind_purpose` is on:
# the release before this one decrypts without a purpose and reads a bound value
# as no value at all, so binding waits until none of its pods can run.
#
# A secret that cannot be decrypted raises DecryptionError. It must never read as
# "no credential": that is how a key mix-up launched sessions without any.
module Encryptable
  extend ActiveSupport::Concern

  class DecryptionError < StandardError
    attr_reader :model, :record_id

    def initialize(message = nil, model: nil, record_id: nil)
      super(message)
      @model = model
      @record_id = record_id
    end
  end

  SALT = "aixle-encryptable-v2"

  included do
    class_attribute :encrypted_columns, instance_writer: false, default: [].freeze
  end

  class_methods do
    def encryption_key(name)
      define_method(:encryption_key_name) { name }
      private :encryption_key_name
    end

    def encrypted_column(*columns)
      self.encrypted_columns = (encrypted_columns + columns.map(&:to_s)).uniq.freeze
    end
  end

  def self.encryptor_for(info, key_name)
    current = Settings.encryption[key_name].to_s
    raise ArgumentError, "[Encryptable] #{info} encryption key is not set" if current.blank?

    encryptor = ActiveSupport::MessageEncryptor.new(derive(current, info))
    previous_keys(key_name).each { |raw| encryptor.rotate(derive(raw, info)) }
    encryptor
  end

  def self.previous_keys(key_name)
    Settings.encryption["#{key_name}_previous"].to_s.split(",").map(&:strip).compact_blank
  end

  def self.derive(raw, info)
    OpenSSL::KDF.hkdf(raw, salt: SALT, info: info, length: 32, hash: "SHA256")
  end

  # Decrypts every encrypted column and writes nothing; raises DecryptionError
  # for the first one no configured key can read.
  def read_secrets!
    encrypted_columns.each { |column| decrypt_secret(self[column], column: column) }
    true
  end

  # Rewrites every encrypted column under the current key and its purpose.
  # Returns true when anything changed.
  def reencrypt_secrets!
    changes = encrypted_columns.each_with_object({}) do |column, memo|
      cipher = self[column]
      next if cipher.blank?

      memo[column] = encrypt_secret(decrypt_secret(cipher, column: column), column: column)
    end
    return false if changes.empty?

    update_columns(changes)
    true
  end

  private

  def encrypt_secret(plaintext, column:)
    return nil if plaintext.nil? || plaintext == ""

    encryptor.encrypt_and_sign(plaintext, purpose: (secret_purpose(column) if Settings.encryption.bind_purpose))
  end

  def decrypt_secret(ciphertext, column:)
    return nil if ciphertext.blank?

    value = encryptor.decrypt_and_verify(ciphertext, purpose: secret_purpose(column))
    value = encryptor.decrypt_and_verify(ciphertext) if value.nil?
    raise undecryptable(column) if value.nil?

    value
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    raise undecryptable(column)
  end

  def secret_purpose(column)
    "#{self.class.base_class.name}.#{column}"
  end

  def undecryptable(column)
    DecryptionError.new("#{self.class.name}##{column} (id=#{id.inspect}) cannot be decrypted with the configured keys",
                        model: self.class.base_class.name, record_id: id)
  end

  def encryptor
    @encryptor ||= Encryptable.encryptor_for(self.class.name, encryption_key_name)
  end

  def encryption_key_name
    raise NotImplementedError, "#{self.class.name} must declare `encryption_key`"
  end
end
