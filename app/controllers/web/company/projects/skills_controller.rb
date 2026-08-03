# frozen_string_literal: true

class Web::Company::Projects::SkillsController < Web::Company::Projects::ApplicationController
  CATALOG_PAGE_SIZE = 60
  # Upstream is rate-limited per IP with no published number, and every debounced
  # keystroke from every member arrives here. Short-lived caching keeps a room full of
  # people typing from spending the whole deployment's budget on the same queries.
  SEARCH_CACHE_TTL = 5.minutes

  def index
    skills = Skill.visible_for_project(current_project).order(created_at: :desc)

    props = {
      project: project_props,
      skills: skills.map { |s| SkillResource.new(s).to_h },
      catalogQuery: catalog_query,
      catalogSkills: catalog_entries.map { |c| CatalogSkillResource.new(c).to_h },
      catalogSyncedAt: CatalogSkill.maximum(:registry_synced_at)
    }

    render inertia: "Projects/Skills/SkillsPage", props: props
  end

  def create
    skill = SkillsRegistryService.install(
      params[:skill_id],
      scope: current_project,
      installs: catalog_installs(params[:skill_id])
    )
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' installed"
  rescue SkillsRegistryService::RegistryError => e
    redirect_to company_project_skills_path(current_project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project), alert: e.record.errors.full_messages.join(", ")
  rescue ActiveRecord::RecordNotUnique
    # Two people (or two clicks) installing the same skill at once: the unique index
    # is doing its job, and this is not a 500.
    redirect_to company_project_skills_path(current_project), alert: "That skill is already installed"
  end

  # Register a skill written by hand rather than installed from the registry.
  #
  # `name` and `description` come from the pasted frontmatter and nowhere else: the
  # Agent Skills spec requires a skill's name to equal its directory name, and a
  # second source of truth for the name is exactly how that invariant breaks.
  #
  # Validation failures come back as Inertia errors rather than a flash, so the modal
  # can show them next to the field WITHOUT discarding what the user pasted.
  def manual
    result = Skills::SkillMarkdown.parse(params[:content])

    unless result.valid?
      redirect_to company_project_skills_path(current_project),
                  inertia: { errors: { content: result.error_sentence } }
      return
    end

    skill = current_project.skills.create!(
      name: result.name,
      title: result.frontmatter["title"].presence || result.name,
      description: result.description,
      content: result.content,
      origin: :manual
    )
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' added"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: e.record.errors.full_messages.join(", ") } }
  rescue ActiveRecord::RecordNotUnique
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: "A skill with that name already exists in this project" } }
  end

  def destroy
    skill = Skill.visible_for_project(current_project).find_by(id: params[:id])

    unless skill
      redirect_to company_project_skills_path(current_project), alert: "Skill not found"
      return
    end

    skill.destroy
    redirect_to company_project_skills_path(current_project), notice: "Skill removed"
  end

  private

  def catalog_query
    params[:catalog_q].to_s.strip
  end

  # Blank (or too-short) query → the default browse view, served from the mirror.
  # A real query → upstream, because skills.sh's fuzzy search beats anything the
  # mirror can do and the mirror is incomplete by construction.
  #
  # NOTHING IS PERSISTED HERE. `index` authorizes as a project READ, so a viewer who
  # is denied `create?` must not be able to write rows into a table shared by every
  # tenant, or trigger an outbound request per keystroke, just by loading a URL.
  # Upstream hits are rendered from unsaved records; the weekly sweep owns the mirror.
  def catalog_entries
    return default_catalog_entries if catalog_query.length < Skills::RegistryClient::MIN_QUERY_LENGTH

    entries = cached_search(catalog_query)
    # Upstream unreachable, or nothing matched: fall back to full-text over whatever
    # is mirrored rather than showing an empty catalog.
    return CatalogSkill.search(catalog_query).limit(CATALOG_PAGE_SIZE) if entries.empty?

    merge_with_mirror(entries)
  end

  def default_catalog_entries
    CatalogSkill.one_per_source.popular.limit(CATALOG_PAGE_SIZE)
  end

  # Recording happens inside the cache-miss block on purpose: a debounced field would
  # otherwise write once per keystroke, and with the 5-minute cache a term is recorded
  # at most once per window no matter how many people are typing it. The term steers a
  # later sweep and is stored unattributed — see CatalogSearchQuery.
  def cached_search(query)
    Rails.cache.fetch([ "skills-catalog-search", query ], expires_in: SEARCH_CACHE_TTL) do
      CatalogSearchQuery.record(query)
      Skills::RegistryClient.search(query, limit: CATALOG_PAGE_SIZE)
    end
  end

  # Upstream relevance order is preserved: the endpoint ranks by fuzzy match, and
  # re-sorting by popularity would push the exact-name hit below a tangential match
  # with more installs. Mirrored rows are reused where they exist so a result keeps
  # its description and audit verdicts; anything unmirrored renders from the search
  # payload alone.
  def merge_with_mirror(entries)
    mirrored = CatalogSkill.where(registry_id: entries.map(&:id).compact).index_by(&:registry_id)

    entries.map { |entry| mirrored[entry.id] || transient_catalog_skill(entry) }
  end

  def transient_catalog_skill(entry)
    source, slug = split_registry_id(entry)

    CatalogSkill.new(
      registry_id: entry.id.presence || "#{source}/#{slug}",
      source: source,
      slug: slug,
      title: (entry.name if entry.name.present? && entry.name != slug),
      installs: entry.installs.to_i
    )
  end

  def split_registry_id(entry)
    parts = entry.id.to_s.split("/").reject(&:blank?)
    return [ entry.source, entry.slug ] if parts.size < 2

    [ parts[0..-2].join("/"), parts.last ]
  end

  # The download endpoint reports no install count, so the figure comes from the
  # catalog row the user clicked — the search endpoint is the only place it exists.
  def catalog_installs(skill_id)
    CatalogSkill.find_by(registry_id: skill_id.to_s)&.installs
  end
end
