# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Alipay
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddAlipayPaymentProvider"
        description "Add or update Alipay payment provider"

        input_object_class Types::PaymentProviders::AlipayInput

        type Types::PaymentProviders::Alipay
      end
    end
  end
end
