# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :context, :record

  def initialize(context, record)
    @record = record
    @context = context
  end

  def user
    context.user
  end
end
