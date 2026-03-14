class Web::PagesController < Web::ApplicationController
  def privacy_policy
    render layout: "web/legal"
  end

  def terms_of_service
    render layout: "web/legal"
  end
end
