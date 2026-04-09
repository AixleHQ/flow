# frozen_string_literal: true

class Web::Company::RepositoriesController < Web::Company::ApplicationController
  def index
    repositories = Repository.for_company(current_company)
                             .includes(:integration)
                             .order(:full_name)

    integrations = current_company.integrations
                                  .company_wide
                                  .active
                                  .where(provider: %i[github gitlab])
                                  .includes(:connected_by)

    props = {
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

    if params[:edit_repo_id].present?
      repo = repositories.find { |r| r.id == params[:edit_repo_id].to_i }
      if repo&.integration
        props[:edit_branches] = RepositoryService.for(repo.integration).list_branches(repo.full_name)
      end
    end

    render inertia: "Company/Repositories/Index", props: props
  end

  def create
    repo = Repository.new(create_params.merge(scope: current_company))

    if repo.save
      redirect_to company_repositories_path, notice: "Repository added"
    else
      redirect_to company_repositories_path, inertia: { errors: repo.errors }
    end
  end

  def update
    repo = Repository.for_company(current_company).find(params[:id])

    if repo.update(update_params)
      redirect_to company_repositories_path, notice: "Repository updated"
    else
      redirect_to company_repositories_path, inertia: { errors: repo.errors }
    end
  end

  def destroy
    repo = Repository.for_company(current_company).find(params[:id])
    repo.destroy
    redirect_to company_repositories_path, notice: "Repository removed"
  end

  private

  def create_params
    params.require(:repository).permit(:full_name, :clone_url, :source_branch, :integration_id, :description, :purpose, :is_private)
  end

  def update_params
    params.require(:repository).permit(:source_branch, :purpose, :description)
  end
end
