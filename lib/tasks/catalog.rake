# frozen_string_literal: true

namespace :catalog do
  namespace :featured do
    desc "Load the committed featured catalog seed (idempotent; never overwrites synced rows)"
    task load: :environment do
      result = Catalog::FeaturedSeed.load!
      puts "Featured catalog seed inserted: #{result}"
    end

    desc "Regenerate db/seeds/catalog/*.json from this database's mirror (run after editing a FEATURED list)"
    task dump: :environment do
      seed = Catalog::FeaturedSeed.new
      result = seed.dump!
      puts "Wrote #{seed.connectors_path} and #{seed.skills_path}: #{result}"

      missing_connectors = Connector::FEATURED - Connector.where(name: Connector::FEATURED).pluck(:name)
      missing_skills = CatalogSkill::FEATURED - CatalogSkill.where(registry_id: CatalogSkill::FEATURED).pluck(:registry_id)
      # A dump can only carry what this database mirrored. Silently emitting a short
      # file is how a FEATURED entry disappears from every fresh deployment unnoticed.
      if missing_connectors.any? || missing_skills.any?
        warn "WARNING: not mirrored here, so absent from the seed — sync first, or drop them from FEATURED:"
        missing_connectors.each { |name| warn "  connector #{name}" }
        missing_skills.each { |id| warn "  skill #{id}" }
      end
    end
  end
end
