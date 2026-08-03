# frozen_string_literal: true

module Skills
  # Writes RegistryClient entries into the catalog mirror.
  #
  # Used by the weekly sweep. NOT used on a web request: a GET must not mutate a
  # global table, and a typed query renders upstream results directly instead.
  #
  # The search endpoint returns a strict subset of what a row can hold — no
  # description, a `name` that is usually the slug repeated, and an `installs` figure
  # that is occasionally absent. So the conflict clause is explicit rather than a
  # blanket column list: a re-sweep must never undo what the metadata backfill
  # resolved, and must never replace a real install count with a zero.
  class CatalogUpsert
    # `excluded` is the row we tried to insert; `catalog_skills` is what is already
    # stored. COALESCE/GREATEST make this pass strictly additive.
    ON_DUPLICATE = Arel.sql(<<~SQL.squish)
      source = excluded.source,
      slug = excluded.slug,
      title = COALESCE(excluded.title, catalog_skills.title),
      installs = GREATEST(excluded.installs, catalog_skills.installs),
      registry_synced_at = excluded.registry_synced_at,
      updated_at = excluded.updated_at
    SQL

    # @return [Array<String>] the registry_ids actually written, so callers never
    #   have to guess how an upstream id was normalised.
    def self.call(entries)
      rows = Array(entries).filter_map { |entry| row_for(entry) }
      # A sweep asks overlapping questions, so the same skill arrives from several
      # seeds. Postgres refuses an ON CONFLICT touching one row twice per statement.
      rows = rows.index_by { |row| row[:registry_id] }.values
      return [] if rows.empty?

      CatalogSkill.upsert_all(rows, unique_by: :registry_id, on_duplicate: ON_DUPLICATE,
                              record_timestamps: false)
      rows.map { |row| row[:registry_id] }
    end

    def self.row_for(entry)
      source, slug = split_id(entry)
      return nil if source.blank? || slug.blank?

      now = Time.current
      {
        registry_id: "#{source}/#{slug}",
        source: source,
        slug: slug,
        # `name` is usually the slug repeated; keep it only when it adds something.
        title: (entry.name if entry.name.present? && entry.name != slug),
        installs: entry.installs.to_i,
        registry_synced_at: now,
        created_at: now,
        updated_at: now
      }
    end

    # Ids look like "owner/repo/slug" — but a non-GitHub publisher's id has only two
    # segments ("open.feishu.cn/lark-doc"), and upstream has been seen emitting
    # leading or doubled slashes. Blank segments are dropped so "owner//slug" cannot
    # mint a phantom row whose package matches nothing.
    def self.split_id(entry)
      parts = entry.id.to_s.split("/").reject(&:blank?)
      return [ entry.source, entry.slug ] if parts.size < 2

      [ parts[0..-2].join("/"), parts.last ]
    end

    private_class_method :row_for, :split_id
  end
end
