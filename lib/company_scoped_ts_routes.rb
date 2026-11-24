# frozen_string_literal: true

# app/frontend/shared/routes.ts, with the helpers of routes under
# /company/:company_slug taking the slug from the tab's own URL, as Rails fills
# it from the request on the server. Their signatures stay what they were, and
# `{ company_slug }` in a call's options names another company. With no slug in
# the URL (/profile, onboarding) the segment is left out, and the server sends
# that path on to the company the person was last on.
class CompanyScopedTsRoutes < TsRoutes::Generator
  HEADER = <<~TS.chomp
    /* tslint:disable */
    import { currentCompanySlug } from '@/shared/lib/currentCompanySlug';
  TS

  RUNTIME = <<~TS
    function $companySegment(options: any): string {
      const slug = options && $isPresent(options.company_slug) ? options.company_slug : currentCompanySlug();
      return slug ? "/" + $encode(slug) : "";
    }
  TS

  def initialize(**)
    super(header: HEADER, **)
  end

  def runtime_ts
    "#{super}\n#{RUNTIME}"
  end

  def build_route_function(route, parent_route = nil)
    function = super
    return function unless route.required_parts.include?(:company_slug)

    { "company_slug: ScalarType, " => "", %("/" + company_slug + ) => "$companySegment(options) + " }.each do |from, to|
      function.sub!(from, to) or raise "ts_routes no longer writes `#{from}` for #{route.name}"
    end
    function
  end
end
