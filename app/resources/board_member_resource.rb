# frozen_string_literal: true

class BoardMemberResource < ApplicationResource
  typelize_from User

  attributes :id, :name
end
