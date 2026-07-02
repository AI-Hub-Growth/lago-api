# frozen_string_literal: true

module PaymentProviders
  module Alipay
    module Customers
      class CreateService < BaseService
        ALIPAY_PAYMENT_METHOD_ID = "alipay"
        ALIPAY_PAYMENT_METHOD_TYPE = "alipay"

        def initialize(customer:, payment_provider_id:, params:, async: true)
          @customer = customer
          @payment_provider_id = payment_provider_id
          @params = params || {}
          @async = async

          super
        end

        def call
          provider_customer = PaymentProviderCustomers::AlipayCustomer.find_by(customer_id: customer.id)
          provider_customer ||= PaymentProviderCustomers::AlipayCustomer.new(
            customer_id: customer.id,
            payment_provider_id:,
            organization_id: organization.id
          )
          provider_customer.payment_provider_id = payment_provider_id if payment_provider_id.present?

          if params.key?(:sync_with_provider)
            provider_customer.sync_with_provider = params[:sync_with_provider].presence
          end

          provider_customer.save!
          ensure_payment_method(provider_customer)

          result.provider_customer = provider_customer
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_reader :customer, :payment_provider_id, :params, :async

        delegate :organization, to: :customer

        def ensure_payment_method(provider_customer)
          payment_method_result = PaymentMethods::FindOrCreateFromProviderService.call(
            customer:,
            payment_provider_customer: provider_customer,
            provider_method_id: ALIPAY_PAYMENT_METHOD_ID,
            params: {
              provider_payment_methods: [ALIPAY_PAYMENT_METHOD_TYPE],
              details: {type: ALIPAY_PAYMENT_METHOD_TYPE}
            },
            set_as_default: true
          )
          payment_method_result.raise_if_error!

          payment_method = payment_method_result.payment_method
          payment_method.update!(
            payment_provider_id: provider_customer.payment_provider_id,
            details: {type: ALIPAY_PAYMENT_METHOD_TYPE}
          ) if payment_method.payment_provider_id != provider_customer.payment_provider_id ||
            payment_method.details != {"type" => ALIPAY_PAYMENT_METHOD_TYPE}
        end
      end
    end
  end
end
