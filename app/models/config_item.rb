# frozen_string_literal: true

class ConfigItem < ApplicationRecord
  include Encryptable
  extend Enumerize

  encryption_key :config_items_key
  encrypted_column :encrypted_value

  # Enumerize for type (adds scopes: with_item_type(:secret), with_scope_type(:company))
  enumerize :item_type, in: %i[secret variable], default: :variable, predicates: true, scope: true

  # Polymorphic scope
  belongs_to :scope, polymorphic: true
  include TenantColumns

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
  validate :value_reentered_to_reveal, on: :update

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

  def picker_name
    name
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

  # Intercept value assignment to handle secrets properly. A blank value leaves the
  # stored one alone: the edit form submits the field empty to mean "keep", and
  # nothing may be set to an empty value anyway (see #value_present_on_create).
  def value=(val)
    @raw_value = val
    super(val) if val.present?
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
    return protect_value_on_type_change if @raw_value.blank?

    if secret?
      self.encrypted_value = encrypt(@raw_value)
      self[:value] = nil
    else
      self.encrypted_value = nil
      self[:value] = @raw_value
    end
    @raw_value = nil # Clear temp value
  end

  # A variable turned into a secret takes its current value along — encrypted, and
  # no longer readable as plaintext.
  def protect_value_on_type_change
    return unless persisted? && will_save_change_to_item_type? && secret? && self[:value].present?

    self.encrypted_value = encrypt(self[:value])
    self[:value] = nil
  end

  # The opposite would put a secret on screen for everyone who can open the page,
  # so the value has to be typed again.
  def value_reentered_to_reveal
    return unless will_save_change_to_item_type? && variable? && self[:value].blank?

    errors.add(:value, "must be entered again to turn a secret into a variable")
  end

  def encrypt(plain_text)
    encrypt_secret(plain_text, column: "encrypted_value")
  end

  def decrypt(cipher_text)
    decrypt_secret(cipher_text, column: "encrypted_value")
  end
end
