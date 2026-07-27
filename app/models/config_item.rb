# frozen_string_literal: true

class ConfigItem < ApplicationRecord
  include Encryptable
  extend Enumerize

  # Enumerize for type (adds scopes: with_item_type(:secret), with_scope_type(:company))
  enumerize :item_type, in: %i[secret variable], default: :variable, predicates: true, scope: true

  # Polymorphic scope
  belongs_to :scope, polymorphic: true

  # Auto-upcase name
  def name=(val)
    super(val&.upcase)
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[A-Z][A-Z0-9_]*\z/, message: "must be uppercase with underscores (e.g., API_KEY)" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :item_type, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }
  validates :scope_id, presence: true

  # Value must be present on create
  validate :value_present_on_create, on: :create

  # Handle encryption before validation (after all attributes are set)
  before_validation :encrypt_value_if_secret

  # Scopes
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  scope :visible_for_project, ->(project) {
    where(scope_type: "Project", scope_id: project.id)
  }

  def scope_indicator
    "project"
  end

  # Get effective config items for container injection (resolved overrides).
  # Config items are Project-scoped. Returns hash { name => decrypted_value }.
  def self.effective_for_project(project)
    for_project(project).index_by(&:name).transform_values(&:decrypted_value)
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name description item_type scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  # Get display value (masked for secrets)
  def display_value
    secret? ? "••••••••" : value
  end

  # Check if value can be displayed
  def value_editable?
    variable?
  end

  # Store raw value temporarily - encryption happens in before_validation
  attr_accessor :raw_value

  # Intercept value assignment to handle secrets properly
  def value=(val)
    @raw_value = val
    super(val)
  end

  # Get decrypted value (for container injection only)
  def decrypted_value
    secret? ? decrypt(encrypted_value) : value
  end

  private

  def value_present_on_create
    if secret?
      errors.add(:value, "can't be blank") if encrypted_value.blank? && @raw_value.blank?
    elsif value.blank? && @raw_value.blank?
      errors.add(:value, "can't be blank")
    end
  end

  def encrypt_value_if_secret
    return unless @raw_value.present?

    if secret?
      self.encrypted_value = encrypt(@raw_value)
      self[:value] = nil
    else
      self.encrypted_value = nil
      self[:value] = @raw_value
    end
    @raw_value = nil # Clear temp value
  end

  def encrypt(plain_text)
    return nil if plain_text.blank?

    encryptor.encrypt_and_sign(plain_text)
  end

  def decrypt(cipher_text)
    return nil if cipher_text.blank?

    encryptor.decrypt_and_verify(cipher_text)
  # AES-GCM raises InvalidMessage on a wrong/rotated key; InvalidSignature is the
  # CBC-era name. Rescue both so an un-recrypted row degrades to nil instead of
  # 500ing during the key-migration window (mirrors the other Encryptable models).
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def encryption_key_setting
    Settings.encryption.config_items_key
  end
end
