# frozen_string_literal: true

# The public template catalog (design D16): readable without signing in.
# Installing goes through Web::Company::TemplateInstallsController, in the
# company the person was last on; a guest signs in first and is brought back to
# the version they saw.
class Web::TemplatesController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  def index
    templates = CatalogTemplate.listed.order(install_count: :desc, name: :asc)
    publishers = CatalogNamespace.all.index_by(&:name)
    render inertia: "Templates/IndexPage", props: {
      templates: templates.map { |template| Templates::Presenter.summary(template, publishers: publishers) },
      signed_in: signed_in?
    }
  end

  def show
    template = CatalogTemplate.find_by!(namespace: params[:namespace], slug: params[:slug])
    render inertia: "Templates/ShowPage", props: {
      template: Templates::Presenter.detail(template),
      install_path: template.revoked? ? nil : install_template_path(template.namespace, template.slug, version: template.version),
      signed_in: signed_in?
    }
  end

  def install
    install = { namespace: params[:namespace], slug: params[:slug], version: params[:version].to_i }
    return redirect_to(new_company_template_install_path(**install)) if signed_in? && current_company

    remember_pending_template_install(**install)
    redirect_to login_path
  end
end
