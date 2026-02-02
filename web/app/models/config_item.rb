# frozen_string_literal: true

class ConfigItem < ApplicationRecord
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
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true

  # Value must be present on create
  validate :value_present_on_create, on: :create

  # Scopes
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

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

  # Set value (handles encryption for secrets)
  def value=(val)
    if secret?
      self.encrypted_value = encrypt(val) if val.present?
      super(nil)
    else
      self.encrypted_value = nil
      super(val)
    end
  end

  # Get decrypted value (for container injection only)
  def decrypted_value
    secret? ? decrypt(encrypted_value) : value
  end

  private

  def value_present_on_create
    if secret?
      errors.add(:value, "can't be blank") if encrypted_value.blank?
    elsif value.blank?
      errors.add(:value, "can't be blank")
    end
  end

  def encrypt(plain_text)
    return nil if plain_text.blank?

    encryptor.encrypt_and_sign(plain_text)
  end

  def decrypt(cipher_text)
    return nil if cipher_text.blank?

    encryptor.decrypt_and_verify(cipher_text)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  def encryption_key
    Settings.encryption.config_items_key.to_s.ljust(32, "0")[0..31]
  end
end
