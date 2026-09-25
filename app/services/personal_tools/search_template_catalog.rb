# frozen_string_literal: true

module PersonalTools
  # The template catalog, as its public page browses it.
  class SearchTemplateCatalog < Base
    tool do
      display_name "Search Template Catalog"
      description "Search the template catalog: ready-made connectors, boards, workflows and whole projects " \
                  "reviewed by the Flow maintainers. Omit the query to list everything. Read one with " \
                  "get_template, then install_template."
      audience :user
      tags :templates
      read_only
      param :query, type: :string, description: "Words to match in the name or summary."
      param :kind, type: :string, enum: Templates::Package::KINDS, description: "Only templates of this kind."
      param :namespace, type: :string, description: "Only templates of this publisher (namespace)."
    end

    LIMIT = 50

    def execute
      scope = CatalogTemplate.listed.order(install_count: :desc, name: :asc)
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      scope = scope.where(namespace: params[:namespace]) if params[:namespace].present?
      if params[:query].present?
        pattern = "%#{CatalogTemplate.sanitize_sql_like(params[:query].to_s.strip)}%"
        scope = scope.where("name ILIKE :q OR summary ILIKE :q", q: pattern)
      end
      publishers = CatalogNamespace.all.index_by(&:name)
      success(results: scope.limit(LIMIT).map { |template| Templates::Presenter.summary(template, publishers: publishers) })
    end
  end
end
