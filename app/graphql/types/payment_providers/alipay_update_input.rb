# frozen_string_literal: true

module Types
  module PaymentProviders
    class AlipayUpdateInput < BaseInputObject
      description "Alipay update input arguments"

      argument :alipay_public_key, String, required: false
      argument :app_id, String, required: false
      argument :app_private_key, String, required: false
      argument :code, String, required: false
      argument :environment, Types::PaymentProviders::AlipayEnvironmentEnum, required: false
      argument :id, ID, required: true
      argument :name, String, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
