# frozen_string_literal: true

module PersonalTools
  # Paging, sort and date filters shared by list_sessions and list_workflow_runs,
  # the two halves of the Sessions & Runs list.
  module SessionListSupport
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    DIRECTIONS = %w[asc desc].freeze
    DATE_PARAMS = %i[created_from created_until].freeze

    # Declares the shared params on a tool block's builder: `SessionListSupport.declare_params(self, "runs")`.
    def self.declare_params(dsl, noun)
      dsl.param :created_from, type: :string,
                               description: "Only #{noun} created on or after this day, YYYY-MM-DD (UTC)."
      dsl.param :created_until, type: :string,
                                description: "Only #{noun} created on or before this day, YYYY-MM-DD (UTC)."
      dsl.param :sort, type: :string,
                       description: "Sort column (default created_at). Rows with no value sort last.",
                       enum: SessionListSort::FIELDS
      dsl.param :direction, type: :string, description: "Sort direction (default desc).", enum: DIRECTIONS
      dsl.param :limit, type: :integer, description: "Rows per page (default #{DEFAULT_LIMIT}, cap #{MAX_LIMIT})."
      dsl.param :offset, type: :integer,
                         description: "Rows to skip before the page starts (default 0). Page on with " \
                                      "offset + limit while `has_more` is true."
    end

    private

    # The first refusal among `enums` ({ name => [value, allowed] }) and the date
    # params, or nil when every value given is one the list takes.
    def list_param_refusal(enums)
      enums = enums.merge(sort: [ params[:sort], SessionListSort::FIELDS ], direction: [ params[:direction], DIRECTIONS ])
      enums.each do |name, (value, allowed)|
        next if value.blank? || allowed.include?(value.to_s)

        return "Unknown #{name} '#{value}' — use one of: #{allowed.join(', ')}"
      end
      DATE_PARAMS.each do |name|
        next if params[name].blank? || TerminalSession.parse_filter_date(params[name])

        return "#{name} must be a day as YYYY-MM-DD, got '#{params[name]}'"
      end
      nil
    end

    def requested_sort
      SessionListSort.new("#{params[:sort].presence || SessionListSort::DEFAULT_FIELD} #{params[:direction]}")
    end

    def requested_limit
      params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    end

    def requested_offset
      [ params[:offset].to_i, 0 ].max
    end

    def page_fields(total:, rows:, sort:)
      { sort: sort.to_s, total: total, limit: requested_limit, offset: requested_offset,
        has_more: requested_offset + rows.size < total }
    end
  end
end
