# frozen_string_literal: true

module PaymentProviders
  module Alipay
    module Payments
      class SyncPendingService < BaseService
        Result = BaseResult[:synced_count, :skipped_count]

        LOOKBACK_PERIOD = 30.days
        SUCCESS_CODE = "10000"

        PAYMENT_SERVICE_CLASS_MAP = {
          "Invoice" => Invoices::Payments::AlipayService,
          "PaymentRequest" => PaymentRequests::Payments::AlipayService
        }.freeze

        def call
          result.synced_count = 0
          result.skipped_count = 0

          pending_alipay_payments.find_each do |payment|
            sync_payment(payment)
          end

          result
        end

        private

        def pending_alipay_payments
          Payment
            .joins(:payment_provider)
            .where(payment_providers: {type: "PaymentProviders::AlipayProvider"})
            .where(payable_payment_status: %w[pending processing])
            .where.not(provider_payment_id: nil)
            .where("payments.created_at >= ?", LOOKBACK_PERIOD.ago)
        end

        def sync_payment(payment)
          response = client(payment.payment_provider).trade_query(out_trade_no: payment.provider_payment_id)
          return skip_payment(payment, response) unless response["code"] == SUCCESS_CODE
          return skip_payment(payment, response) if response["trade_status"].blank?

          payable_payment_status = payment.payment_provider.determine_payment_status(response["trade_status"])
          return skip_payment(payment, response) if payable_payment_status.to_s == payment.payable_payment_status

          payment_amount_cents = amount_cents(response, payment)
          return skip_payment(payment, response) if payment_amount_cents.blank?

          payment_service_class(payment).new.update_payment_status(
            organization_id: payment.organization_id,
            status: response["trade_status"],
            alipay_payment: PaymentProviders::AlipayProvider::AlipayPayment.new(
              id: payment.provider_payment_id,
              status: response["trade_status"],
              amount_cents: payment_amount_cents,
              metadata: {}
            )
          ).raise_if_error!

          result.synced_count += 1
        rescue LagoHttpClient::HttpError, BaseService::FailedResult => e
          log_skip(payment, e.message)
          result.skipped_count += 1
        end

        def skip_payment(payment, response)
          log_skip(payment, "response=#{response.slice("code", "sub_code", "msg", "sub_msg", "trade_status")}")
          result.skipped_count += 1
        end

        def payment_service_class(payment)
          PAYMENT_SERVICE_CLASS_MAP.fetch(payment.payable_type) do
            raise BaseService::ServiceFailure.new(
              result,
              code: "unsupported_payable_type",
              error_message: "Unsupported payable type #{payment.payable_type}"
            )
          end
        end

        def amount_cents(response, payment)
          return if response["total_amount"].blank?

          Money.from_amount(response["total_amount"].to_d, payment.amount_currency).cents
        end

        def client(payment_provider)
          PaymentProviders::Alipay::Client.new(payment_provider:)
        end

        def log_skip(payment, message)
          Rails.logger.info("Alipay payment sync skipped payment_id=#{payment.id}: #{message}")
        end
      end
    end
  end
end
