# frozen_string_literal: true

class Company < ApplicationRecord
  extend Enumerize

  enumerize :status, in: %i[active suspended archived], default: :active, predicates: true, scope: true

  # Associations
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }

  # Callbacks
  before_validation :generate_slug, on: :create

  private

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    # Ensure uniqueness
    counter = 1
    while Company.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
end
