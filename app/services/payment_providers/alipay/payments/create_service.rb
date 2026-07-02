# frozen_string_literal: true

module PaymentProviders
  module Alipay
    module Payments
      class CreateService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata

          super
        end

        def call
          return result.single_validation_failure!(error_code: "unsupported_currency") unless payment.amount_currency&.casecmp?("CNY")

          payment.provider_payment_id ||= provider_payment_id
          payment.status = "WAIT_BUYER_PAY"
          payment.payable_payment_status = payment.payment_provider.determine_payment_status(payment.status)
          payment.save!

          result.payment = payment
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_reader :payment, :reference, :metadata

        def provider_payment_id
          "#{payable_prefix}_#{payment.payable_id.delete("-")}_#{SecureRandom.hex(6)}"
        end

        def payable_prefix
          payment.payable_type == "PaymentRequest" ? "pr" : "inv"
        end
      end
    end
  end
end
