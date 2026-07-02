# frozen_string_literal: true

module PaymentProviders
  module Alipay
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        NON_BLOCKING_SUB_CODES = %w[
          ACQ.TRADE_NOT_EXIST
          ACQ.TRADE_STATUS_ERROR
        ].freeze

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          response = client.close(out_trade_no: payment.provider_payment_id)

          if response["code"] == "10000"
            payment.status = "TRADE_CLOSED"
            payment.payable_payment_status = payment.payment_provider.determine_payment_status(payment.status)
            payment.save!

            result.payment = payment
            return result
          end

          return non_blocking_failure(response) if response["sub_code"].in?(NON_BLOCKING_SUB_CODES)

          result.service_failure!(
            code: response["sub_code"] || response["code"],
            message: response["sub_msg"] || response["msg"] || "Alipay payment close failed"
          )
        rescue LagoHttpClient::HttpError => e
          raise Invoices::Payments::ConnectionError, e
        end

        private

        attr_reader :payment

        def non_blocking_failure(response)
          Rails.logger.info(
            "Alipay payment not closeable for payment #{payment.id}: " \
            "code=#{response["code"]} sub_code=#{response["sub_code"]} message=#{response["sub_msg"] || response["msg"]}"
          )

          result.payment = payment
          result
        end

        def client
          @client ||= ::PaymentProviders::Alipay::Client.new(payment_provider: payment.payment_provider)
        end
      end
    end
  end
end
