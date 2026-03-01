# frozen_string_literal: true

module Api
  module V1
    class ContactRequestsController < ApplicationController
      skip_before_action :authenticate_user!

      def create
        contact = ContactRequest.new(contact_params)

        if contact.save
          render json: { message: "ok" }, status: :created
        else
          render json: { error: contact.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def contact_params
        params.require(:contact_request).permit(:first_name, :last_name, :email)
      end
    end
  end
end
