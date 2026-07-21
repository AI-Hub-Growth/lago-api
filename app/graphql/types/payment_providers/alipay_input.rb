# frozen_string_literal: true

module Types
  module PaymentProviders
    class AlipayInput < BaseInputObject
      description "Alipay input arguments"

      argument :alipay_public_key, String, required: true
      argument :app_id, String, required: true
      argument :app_private_key, String, required: true
      argument :code, String, required: true
      argument :environment, Types::PaymentProviders::AlipayEnvironmentEnum, required: false
      argument :name, String, required: true
      argument :success_redirect_url, String, required: false
    end
  end
end
