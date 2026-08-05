# frozen_string_literal: true

class Web::Company::Projects::RepositoriesController < Web::Company::Projects::ApplicationController
  def index
    repositories = Repository.visible_for_project(current_project)
                             .includes(:integration)
                             .order(:full_name)

    integrations = Integration.visible_for_project(current_project)
                              .active
                              .where(provider: %i[github gitlab])
                              .includes(:connected_by)

    props = {
      project: project_props,
      repositories: repositories.map { |r| RepositoryResource.new(r).to_h },
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h }
    }

    if params[:integration_id].present?
      integration = integrations.find { |i| i.id == params[:integration_id].to_i }
      if integration
        props[:available_repos] = RepositoryService.for(integration).list_available.map do |r|
          { fullName: r[:full_name], defaultBranch: r[:default_branch] }
        end

        if params[:repo].present?
          props[:available_branches] = RepositoryService.for(integration).list_branches(params[:repo])
        end
      end
    end

    render inertia: "Projects/Repositories/RepositoriesPage", props: props
  end

  def create
    repo =
      if public_params[:public_url].present?
        begin
          build_public_repository
        rescue PublicRepositoryService::Error => e
          return redirect_to company_project_repositories_path(current_project),
                             inertia: { errors: { public_url: e.message } }
        end
      else
        Repository.new(create_params.merge(scope: current_project))
      end

    if repo.save
      redirect_to company_project_repositories_path(current_project), notice: "Repository added"
    else
      redirect_to company_project_repositories_path(current_project), inertia: { errors: repo.errors }
    end
  end

  def update
    repo = Repository.visible_for_project(current_project).find(params[:id])

    if repo.update(update_params)
      redirect_to company_project_repositories_path(current_project), notice: "Repository updated"
    else
      redirect_to company_project_repositories_path(current_project), inertia: { errors: repo.errors }
    end
  end

  def destroy
    repo = Repository.visible_for_project(current_project).find(params[:id])
    repo.destroy
    redirect_to company_project_repositories_path(current_project), notice: "Repository removed"
  end

  private

  # A public repository is verified against the host's public API before it is
  # attached: it must exist and be public, or an anonymous clone would fail
  # inside the session with nothing to explain it. The clone url comes from the
  # resolver, never from the request.
  def build_public_repository
    resolved = PublicRepositoryService.resolve(public_params[:public_url])
    attributes = resolved.to_repository_attributes
    attributes[:source_branch] = public_params[:source_branch] if public_params[:source_branch].present?

    Repository.new(attributes.merge(scope: current_project, purpose: public_params[:purpose]))
  end

  # clone_url is derived (from the integration's provider, or from the resolver)
  # and never accepted from the client: it reaches a `git clone` command line in
  # the session container.
  def create_params
    params.require(:repository).permit(:full_name, :source_branch, :integration_id, :description, :purpose, :is_private)
  end

  def public_params
    params.require(:repository).permit(:public_url, :source_branch, :purpose)
  end

  def update_params
    params.require(:repository).permit(:source_branch, :purpose, :description)
  end
end
