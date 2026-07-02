# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Alipay
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateAlipayPaymentProvider"
        description "Update Alipay payment provider"

        input_object_class Types::PaymentProviders::AlipayUpdateInput

        type Types::PaymentProviders::Alipay
      end
    end
  end
end
