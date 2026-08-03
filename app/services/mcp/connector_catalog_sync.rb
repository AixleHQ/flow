# frozen_string_literal: true

module MCP
  # Refreshes the local connector catalog from the Official MCP Registry.
  #
  # Idempotent and gap-tolerant by construction: it resumes from the newest
  # `registry_updated_at` already mirrored and asks the registry for everything
  # changed since. Running it twice converges; missing a day converges; a first
  # run with an empty table walks the whole registry.
  #
  # That property is deliberate rather than incidental — this codebase has
  # already been bitten by a scheduler losing dynamic schedules on redeploy, so
  # the sync must not depend on its own cadence being honoured.
  #
  # Deleted entries are UPSERTED, not destroyed: the registry reports deletions
  # (any `updated_since` query includes them), and a project that already
  # installed such a connector needs the row to keep explaining its provenance
  # and to power the warning. Discovery filters them out instead — see
  # Connector.discoverable.
  class ConnectorCatalogSync
    # Re-mirror slightly before the newest known change, so an entry written
    # during the previous run's own page walk cannot fall through the crack
    # between "fetched" and "saved". Generous relative to the run itself: the
    # sync is weekly, so a wider overlap costs almost nothing and a missed entry
    # would go unnoticed for seven days.
    OVERLAP = 1.hour

    Result = Struct.new(:fetched, :upserted, :failed, :interrupted, keyword_init: true) do
      def to_s = "fetched=#{fetched} upserted=#{upserted} failed=#{failed}#{' INTERRUPTED' if interrupted}"
    end

    def self.call(full: false) = new(full: full).call

    def initialize(full: false)
      @full = full
      @result = Result.new(fetched: 0, upserted: 0, failed: 0, interrupted: false)
    end

    def call
      since = @full ? nil : watermark
      Rails.logger.info("[ConnectorCatalogSync] Starting (#{since ? "since #{since.iso8601}" : 'full'})")

      begin
        ConnectorRegistryClient.each_updated_since(since) do |manifests|
          @result.fetched += manifests.size
          upsert_page(manifests)
        end
      rescue ConnectorRegistryClient::WalkInterrupted => e
        # Everything fetched so far is already mirrored and stays. What must not
        # happen is calling it a complete sync: the watermark is derived from
        # mirrored data, so the next run picks up from where this one truly got
        # to rather than from where it claimed to.
        @result.interrupted = true
        Rails.logger.warn("[ConnectorCatalogSync] #{e.message}")
      end

      refresh_ranking
      Rails.logger.info("[ConnectorCatalogSync] Finished #{@result}")
      @result
    end

    private

    # Ranking signals the registry cannot supply. Recomputed wholesale rather
    # than incremented on install: it is two statements over a small table, and
    # a counter that drifts from reality is worse than one recomputed weekly.
    def refresh_ranking
      counts = MCPServer.where.not(connector_name: nil).group(:connector_name).count
      Connector.where.not(install_count: 0).where.not(name: counts.keys).update_all(install_count: 0)
      counts.each { |name, count| Connector.where(name: name).update_all(install_count: count) }

      Connector.where(featured: true).where.not(name: Connector::FEATURED).update_all(featured: false)
      Connector.where(name: Connector::FEATURED).update_all(featured: true)

      refresh_bulk_publishers
    end

    # Marks namespaces that publish at scale. Computed from the mirror itself, so
    # it needs no maintained list and adapts as the registry grows.
    def refresh_bulk_publishers
      Connector.connection.execute(<<~SQL.squish)
        UPDATE connectors SET bulk_publisher = sub.bulk
        FROM (
          SELECT name,
                 (COUNT(*) OVER (PARTITION BY split_part(name, '/', 1))
                    >= #{Connector::BULK_PUBLISHER_THRESHOLD}) AS bulk
          FROM connectors
        ) AS sub
        WHERE connectors.name = sub.name AND connectors.bulk_publisher IS DISTINCT FROM sub.bulk
      SQL
    end

    # nil when nothing is mirrored yet — or when the mirror was built by an older
    # normalizer, which the client turns into a full walk.
    #
    # An incremental sync only re-fetches what the REGISTRY changed, so a change
    # on OUR side (see MCP::ConnectorManifest::VERSION) would otherwise never
    # reach rows the registry left alone. Re-walking is cheap relative to serving
    # a catalog that quietly describes the world under superseded rules.
    def watermark
      return nil if stale_normalization?

      newest = Connector.maximum(:registry_updated_at)
      newest && (newest - OVERLAP)
    end

    def stale_normalization?
      Connector.where(normalizer_version: nil)
               .or(Connector.where.not(normalizer_version: ConnectorManifest::VERSION.to_s))
               .exists?
    end

    def upsert_page(manifests)
      rows = manifests.filter_map { |manifest| row_for(manifest) }
      # A page can still carry the same server twice — the registry is asked for
      # latest versions only, but a server republished mid-walk can appear on two
      # pages, and Postgres refuses an ON CONFLICT that touches a row twice in
      # one statement. Last occurrence wins; the walk is ordered by cursor, so
      # that is the newer record.
      rows = rows.index_by { |row| row[:name] }.values
      return if rows.empty?

      # One statement per page keeps a ~10k-server walk to ~100 writes. `name`
      # is the natural key; nothing references these rows by id, so churning
      # ids on conflict would be harmless anyway.
      #
      # record_timestamps: false because the rows already carry explicit
      # created_at/updated_at — letting Rails add its own as well produces
      # "multiple assignments to same column".
      Connector.upsert_all(rows, unique_by: :name, update_only: UPDATABLE_COLUMNS, record_timestamps: false)
      @result.upserted += rows.size
    rescue ActiveRecord::ActiveRecordError => e
      # A bad page must not abandon the walk: the next scheduled run retries it,
      # and the watermark has not advanced past it.
      @result.failed += rows.size
      Rails.logger.error("[ConnectorCatalogSync] Page upsert failed: #{e.message}")
    end

    UPDATABLE_COLUMNS = %i[version title description repository_url manifest status is_latest registry_updated_at
                           normalizer_version updated_at].freeze

    def row_for(manifest)
      return nil if manifest["name"].blank?

      now = Time.current
      {
        name: manifest["name"],
        version: manifest["version"],
        title: manifest["title"],
        description: manifest["description"],
        repository_url: manifest["repository_url"],
        manifest: manifest,
        status: normalized_status(manifest["status"]),
        is_latest: manifest.fetch("is_latest", true),
        registry_updated_at: parse_time(manifest["updated_at"]),
        normalizer_version: manifest["normalizer_version"].to_s,
        created_at: now,
        updated_at: now
      }
    end

    # An unrecognised upstream status must not blow up the sync or, worse, be
    # coerced to "active" and shown as if it were healthy.
    def normalized_status(status)
      Connector.status.values.include?(status.to_s) ? status.to_s : "deprecated"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
