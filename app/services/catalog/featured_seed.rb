# frozen_string_literal: true

module Catalog
  # The committed slice of the two mirrored catalogs.
  #
  # WHY THIS EXISTS: both mirrors are filled by sweeps over someone else's registry
  # (MCP::ConnectorCatalogSync, Skills::CatalogSync). A deployment that has never run
  # one — a self-hosted install on its first boot above all — opens the Connectors and
  # Skills pages on an empty grid and stays there until a Temporal worker is up and a
  # weekly schedule fires. Worse for skills: descriptions are backfilled from GitHub,
  # which without a read token is 60 requests per hour for the whole deployment, so a
  # cold catalog stays a wall of untitled cards for weeks.
  #
  # So the curated seed both catalogs already rank first (Connector::FEATURED,
  # CatalogSkill::FEATURED) is committed to the repo as JSON and loaded at boot. No
  # network, no token, no worker, no registry load.
  #
  # This is a DISPLAY seed, not an install path: MCP::ConnectorInstaller re-fetches the
  # manifest from the registry at install time and falls back to the mirrored copy only
  # when the registry is unreachable.
  class FeaturedSeed
    DIR = Rails.root.join("db/seeds/catalog")

    # Columns that travel. Deliberately explicit rather than "every attribute minus a
    # few": the file is persisted data, so a new column must be an intentional addition
    # to it instead of something a dump quietly starts emitting.
    #
    # What is absent matters more than what is present:
    #   install_count       — demand on THIS platform. A fresh deployment has none, and
    #                         shipping someone else's would corrupt the ranking's only
    #                         first-party signal.
    #   featured            — derived from the constants at load time, so the curated
    #                         list stays the single source of truth and a stale file
    #                         cannot leave `featured: true` on a dropped entry.
    #   registry_updated_at — see #connector_rows. Load-bearing NULL.
    #   audit, audit_risk   — a security verdict frozen in git would keep asserting
    #                         "safe" months after the providers changed their minds.
    #                         Absent reads as "nobody audited this", which is honest and
    #                         is a state CatalogSkill already distinguishes from safe.
    CONNECTOR_COLUMNS = %i[
      name title description repository_url version status is_latest
      bulk_publisher normalizer_version manifest
    ].freeze

    SKILL_COLUMNS = %i[
      registry_id source slug title description installs bulk_publisher registry_synced_at
    ].freeze

    Result = Struct.new(:connectors, :skills, keyword_init: true) do
      def to_s = "connectors=#{connectors} skills=#{skills}"
    end

    def self.load!(dir: DIR) = new(dir: dir).load!
    def self.dump!(dir: DIR) = new(dir: dir).dump!

    def initialize(dir: DIR)
      @dir = Pathname.new(dir)
    end

    # Inserts what is missing and updates nothing. Idempotent by construction, and safe
    # to run on every boot: a row a sweep has already written is fresher than anything
    # committed to the repo and must never be downgraded to it.
    def load!
      result = Result.new(
        connectors: insert(Connector, :name, connector_rows),
        skills: insert(CatalogSkill, :registry_id, skill_rows)
      )
      Rails.logger.info("[Catalog::FeaturedSeed] Loaded #{result}")
      result
    end

    # Regenerates the committed files from this database's mirror. A maintenance task,
    # run by hand after editing either FEATURED list — see lib/tasks/catalog.rake.
    def dump!
      FileUtils.mkdir_p(@dir)
      connectors = dump_rows(Connector.where(name: Connector::FEATURED).order(:name), CONNECTOR_COLUMNS)
      skills = dump_rows(CatalogSkill.where(registry_id: CatalogSkill::FEATURED).order(:registry_id), SKILL_COLUMNS)

      write(connectors_path, connectors)
      write(skills_path, skills)
      Result.new(connectors: connectors.size, skills: skills.size)
    end

    def connectors_path = @dir.join("connectors.json")
    def skills_path = @dir.join("skills.json")

    private

    def connector_rows
      now = Time.current

      read(connectors_path).filter_map do |entry|
        next unless Connector::FEATURED.include?(entry["name"])

        row(entry, CONNECTOR_COLUMNS).merge(
          featured: true,
          # NOT the dumped value, and this is the whole reason the column is listed
          # here: ConnectorCatalogSync#watermark resumes from MAX(registry_updated_at).
          # A seed claiming a recent registry timestamp would make the very first sync
          # ask the registry for "everything changed since then", mirror nothing, and
          # freeze the catalog at these few dozen rows permanently. NULL states what is
          # actually true — a snapshot committed to a repo knows nothing about the
          # registry's current state — and produces a full walk.
          registry_updated_at: nil,
          created_at: now,
          updated_at: now
        )
      end
    end

    def skill_rows
      now = Time.current

      read(skills_path).filter_map do |entry|
        next unless CatalogSkill::FEATURED.include?(entry["registry_id"])

        # `registry_synced_at` IS kept, unlike its connector counterpart. It is not a
        # watermark — the skills sweep has none — and Skills::CatalogSync destroys rows
        # that carry NULL there, reading it as "no sweep has ever seen this upstream".
        # A dump was taken from a swept mirror, so the timestamp is true, and it keeps
        # the seed out of the phantom-dropper.
        row(entry, SKILL_COLUMNS).merge(featured: true, created_at: now, updated_at: now)
      end
    end

    def row(entry, columns) = columns.index_with { |column| entry[column.to_s] }

    def dump_rows(scope, columns)
      scope.map { |record| columns.index_with { |column| dump_value(record[column]) } }
    end

    # Times go out as ISO8601 rather than through Time#to_s, so the file says what it
    # means in every locale and reads back the same way it was written.
    def dump_value(value) = value.is_a?(Time) ? value.utc.iso8601 : value

    def insert(model, unique_by, rows)
      return 0 if rows.empty?

      model.insert_all(rows, unique_by: unique_by, record_timestamps: false).length
    end

    # A missing or unreadable seed degrades the first impression; it must never stop a
    # deployment from booting, so both are logged and treated as "no seed".
    def read(path)
      unless path.exist?
        Rails.logger.warn("[Catalog::FeaturedSeed] Missing seed file #{path}")
        return []
      end

      JSON.parse(path.read).fetch("entries", [])
    rescue JSON::ParserError => e
      Rails.logger.error("[Catalog::FeaturedSeed] Unreadable seed file #{path}: #{e.message}")
      []
    end

    def write(path, entries)
      payload = { "generated_at" => Time.current.utc.iso8601, "count" => entries.size, "entries" => entries }
      path.write("#{JSON.pretty_generate(payload)}\n")
    end
  end
end
