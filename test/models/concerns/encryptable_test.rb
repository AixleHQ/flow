# frozen_string_literal: true

require "test_helper"

class EncryptableTest < ActiveSupport::TestCase
  NEW_KEY = "rotated-key-0123456789abcdef0123456789abcdef"

  setup do
    @project = create(:project, :standalone)
    @item = create(:config_item, scope: @project, name: "ROTATED", item_type: :secret, value: "rot-123")
  end

  def with_encryption(**values)
    before = values.keys.index_with { |key| Settings.encryption[key] }
    values.each { |key, value| Settings.encryption[key] = value }
    yield
  ensure
    before.each { |key, value| Settings.encryption[key] = value }
  end

  def reread(record) = record.class.find(record.id)

  test "a retired key still reads, and re-encryption moves every secret onto the current one" do
    old_key = Settings.encryption.config_items_key

    with_encryption(config_items_key: NEW_KEY, config_items_key_previous: old_key) do
      rotated = reread(@item)
      assert_equal "rot-123", rotated.decrypted_value
      assert rotated.reencrypt_secrets!
    end

    with_encryption(config_items_key: NEW_KEY, config_items_key_previous: nil) do
      assert_equal "rot-123", reread(@item).decrypted_value
    end
  end

  test "a secret no configured key can read raises instead of reading as empty" do
    with_encryption(config_items_key: NEW_KEY) do
      error = assert_raises(Encryptable::DecryptionError) { reread(@item).decrypted_value }
      assert_equal [ "ConfigItem", @item.id ], [ error.model, error.record_id ]
    end
  end

  test "a read-only check finds a secret no configured key can read and changes nothing" do
    stored = @item.encrypted_value

    assert reread(@item).read_secrets!
    with_encryption(config_items_key: NEW_KEY) do
      assert_raises(Encryptable::DecryptionError) { reread(@item).read_secrets! }
    end
    assert_equal stored, reread(@item).encrypted_value
  end

  test "an unreadable agent credential is refused, never taken for one with no credentials" do
    credential = create(:agent_credential, user: create(:user, :with_company), agent_type: "claude_code")

    with_encryption(credentials_key: NEW_KEY) do
      assert_raises(Encryptable::DecryptionError) { reread(credential).config_data }
    end
  end

  # Ciphertexts from before purposes existed must keep reading until the
  # re-encrypt task binds them.
  test "a ciphertext written without a purpose reads, and is bound to its column once re-encrypted" do
    unbound = unbound_encryptor
    @item.update_columns(encrypted_value: unbound.encrypt_and_sign("legacy-value"))

    with_encryption(bind_purpose: true) do
      legacy = reread(@item)
      assert_equal "legacy-value", legacy.decrypted_value
      legacy.reencrypt_secrets!

      assert_nil unbound.decrypt_and_verify(reread(@item).encrypted_value)
      assert_equal "legacy-value", reread(@item).decrypted_value
    end
  end

  # The previous release decrypts without a purpose, and it runs beside this one
  # during a rolling deploy and again after a rollback.
  test "until purpose binding is switched on, what this release writes the previous one still reads" do
    @item.update!(value: "written-now")

    assert_equal "written-now", unbound_encryptor.decrypt_and_verify(reread(@item).encrypted_value)
  end

  private

  def unbound_encryptor
    ActiveSupport::MessageEncryptor.new(Encryptable.derive(Settings.encryption.config_items_key, "ConfigItem"))
  end
end
