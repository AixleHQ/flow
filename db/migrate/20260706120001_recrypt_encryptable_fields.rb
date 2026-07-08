# frozen_string_literal: true

# Re-encrypts all Encryptable model columns from the old zero-padded KDF to
# HKDF-SHA256. MUST run (and succeed) before deploying the updated
# Encryptable concern — deploying the code first will make existing records
# unreadable.
#
# Run against a production DB backup first to verify correctness and estimate
# runtime. The migration is irreversible; take a snapshot before running.
class RecryptEncryptableFields < ActiveRecord::Migration[8.1]
  def up
    [
      { klass: "AgentCredential", key: Settings.encryption.credentials_key,  columns: [ :encrypted_config_data ] },
      { klass: "ConfigItem",      key: Settings.encryption.config_items_key,  columns: [ :encrypted_value ] },
      { klass: "Integration",     key: Settings.encryption.integrations_key,  columns: [ :credentials ] }
    ].each do |spec|
      raw_key = spec[:key].to_s
      old_key = raw_key.ljust(32, "0")[0..31]
      new_key = OpenSSL::KDF.hkdf(raw_key, salt: "aixle-encryptable-v2", info: spec[:klass], length: 32, hash: "SHA256")

      old_encryptor = ActiveSupport::MessageEncryptor.new(old_key)
      new_encryptor = ActiveSupport::MessageEncryptor.new(new_key)

      spec[:klass].constantize.find_each do |record|
        spec[:columns].each do |col|
          ciphertext = record.read_attribute(col)
          next if ciphertext.blank?

          begin
            plaintext = old_encryptor.decrypt_and_verify(ciphertext)
            record.update_column(col, new_encryptor.encrypt_and_sign(plaintext))
          rescue ActiveSupport::MessageEncryptor::InvalidMessage,
                 ActiveSupport::MessageVerifier::InvalidSignature => e
            warn "[RecryptEncryptableFields] Skipped #{spec[:klass]}##{record.id} #{col}: #{e.class}"
          end
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
