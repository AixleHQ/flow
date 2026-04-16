# frozen_string_literal: true

# Administrate applies each dashboard's +collection_includes+ to nested +HasMany+ rows on
# parent show pages. Parent-scoped +belongs_to+ associations are often preloaded but never read
# (Bullet: unused eager loading). This mixin removes listed associations from the default
# +collection_includes+; {Admin::ApplicationController} merges them back for +index+ only.
module SkipAdministrateCollectionIncludes
  extend ActiveSupport::Concern

  class_methods do
    def skip_administrate_collection_includes(*associations)
      @skipped_administrate_collection_includes = associations.flatten.map(&:to_sym).freeze
    end

    def skipped_administrate_collection_includes
      @skipped_administrate_collection_includes || [].freeze
    end
  end

  def collection_includes
    super - self.class.skipped_administrate_collection_includes
  end
end
