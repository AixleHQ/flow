# frozen_string_literal: true

# One-shot re-encryption of every Encryptable column from the OLD key scheme
# (raw secret zero-padded/truncated to 32 bytes) to the NEW scheme used by
# app/models/concerns/encryptable.rb (HKDF-SHA256, salt "aixle-encryptable-v2",
# info = model class name).
#
# WHY THIS EXISTS
#   Encryptable switched key derivation. Ciphertext written under the old key is
#   undecryptable under the new key, so every stored value must be decrypted with
#   the old key and re-encrypted with the new one exactly once.
#
# THE OLD KEY IS HARD-CODED ON PURPOSE
#   Historically these secrets were unset in every deployed environment, so the
#   data was actually encrypted with the committed fallback constants below
#   (padded to 32 bytes). Pinning the legacy secret here — instead of reading it
#   from Settings — makes the OLD side correct regardless of what the env vars
#   are set to now, which is what lets this double as a rotation onto real keys:
#     OLD = pad(legacy_fallback_constant)   (what the data was written with)
#     NEW = HKDF(Settings.encryption.<key>) (the real key the app now reads with)
#   So on production you SET the real *_SECRET_KEY env vars, then run this — the
#   old data is read with the pinned constant and rewritten under the real key.
#
# SAFETY PROPERTIES
#   * Idempotent / re-runnable: each row is probed with the NEW key first; rows
#     already migrated are skipped, so a resumed or repeated run is a no-op.
#   * Never corrupts: a row is rewritten only after a round-trip verify, and the
#     write is per-row, so a row is always either fully-old or fully-new.
#   * Never destroys unreadable data: a value that decrypts under neither key is
#     left untouched and logged (not overwritten).
#   * Fails loud on a wrong key: if a table has rows but none are already-new and
#     none decrypt with the pinned old key, it raises before doing damage.
#   * Self-contained: uses anonymous AR classes bound to table names and hard-
#     coded constants — no dependency on application model code.
#
# DISPOSABLE: once this has run successfully in every environment, the file can
# be deleted outright (nothing references it; the old key material goes with it).
class RecryptEncryptableFields < ActiveRecord::Migration[8.1]
  SALT = "aixle-encryptable-v2"

  # info MUST equal the model class name (Encryptable derives with info: self.class.name).
  # legacy_secret is the pre-migration committed fallback the data was encrypted with.
  SPECS = [
    { model: "AgentCredential", table: "agent_credentials", setting: :credentials_key,  legacy_secret: "test secret key",        columns: %w[encrypted_config_data] },
    { model: "ConfigItem",      table: "config_items",      setting: :config_items_key,  legacy_secret: "config items test key", columns: %w[encrypted_value] },
    { model: "Integration",     table: "integrations",      setting: :integrations_key,  legacy_secret: "integrations test key", columns: %w[credentials] },
    { model: "WebhookEndpoint", table: "webhook_endpoints", setting: :integrations_key,  legacy_secret: "integrations test key", columns: %w[encrypted_secret] },
    { model: "OauthClient",     table: "oauth_clients",     setting: :oauth_key,         legacy_secret: "oauth test key",        columns: %w[encrypted_client_secret] },
    { model: "OauthCredential", table: "oauth_credentials", setting: :oauth_key,         legacy_secret: "oauth test key",        columns: %w[encrypted_access_token encrypted_refresh_token] }
  ].freeze

  def up
    SPECS.each { |spec| recrypt_spec(spec) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def recrypt_spec(spec)
    unless connection.table_exists?(spec[:table])
      say "skipping #{spec[:model]}: table #{spec[:table]} does not exist"
      return
    end

    new_secret = Settings.encryption.public_send(spec[:setting]).to_s
    if new_secret.blank?
      raise "Aborted: Settings.encryption.#{spec[:setting]} is blank — set the env var before running (it is the NEW key #{spec[:model]} is rewritten under)"
    end

    old_encryptor = ActiveSupport::MessageEncryptor.new(spec[:legacy_secret].ljust(32, "0")[0..31])
    new_encryptor = ActiveSupport::MessageEncryptor.new(
      OpenSSL::KDF.hkdf(new_secret, salt: SALT, info: spec[:model], length: 32, hash: "SHA256")
    )

    klass = Class.new(ActiveRecord::Base) { self.table_name = spec[:table] }
    klass.reset_column_information

    migrated = already = failed = 0

    klass.find_each do |row|
      spec[:columns].each do |col|
        ciphertext = row[col]
        next if ciphertext.blank?

        if decryptable?(new_encryptor, ciphertext) # already NEW → skip (idempotent)
          already += 1
          next
        end

        plaintext = safe_decrypt(old_encryptor, ciphertext)
        if plaintext.nil?
          failed += 1
          Rails.logger.error("[recrypt] #{spec[:model]}##{row.id}.#{col}: decrypts under neither new nor legacy key — left untouched")
          next
        end

        new_ciphertext = new_encryptor.encrypt_and_sign(plaintext)
        unless new_encryptor.decrypt_and_verify(new_ciphertext) == plaintext
          raise "[recrypt] round-trip verification failed for #{spec[:model]}##{row.id}.#{col}"
        end

        klass.where(id: row.id).update_all(col => new_ciphertext)
        migrated += 1
      end
    end

    if migrated.zero? && already.zero? && failed.positive?
      raise "[recrypt] #{spec[:model]}: #{failed} rows and NONE decrypt with the pinned legacy key — wrong old key? Aborting before further damage."
    end

    say "#{spec[:model]}: re-encrypted #{migrated}, already-new #{already}, unreadable #{failed}"
  end

  def decryptable?(encryptor, ciphertext)
    !safe_decrypt(encryptor, ciphertext).nil?
  end

  def safe_decrypt(encryptor, ciphertext)
    encryptor.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
