# frozen_string_literal: true

module PaymentRequests
  module Payments
    class AlipayService < BaseService
      include Customers::PaymentProviderFinder
      include Updatable

      PROVIDER_NAME = "Alipay"
      CHECKOUT_PRODUCT_CODE = "FAST_INSTANT_TRADE_PAY"

      def initialize(payable = nil)
        @payable = payable

        super
      end

      def generate_payment_url
        return result.single_validation_failure!(error_code: "unsupported_currency") unless payable.currency&.casecmp?("CNY")

        out_trade_no = reusable_provider_payment_id || provider_payment_id
        params = payment_url_params(out_trade_no)

        result.payment_url = alipay_payment_provider.checkout_session_payment_url(
          checkout_session(out_trade_no, params)
        )

        result
      rescue LagoHttpClient::HttpError => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      end

      def update_payment_status(organization_id:, status:, alipay_payment:)
        payment = Payment.find_or_initialize_by(provider_payment_id: alipay_payment.id)
        payment = create_payment(alipay_payment) unless payment.persisted?
        return result.not_found_failure!(resource: "alipay_payment") unless payment

        result.payment = payment
        result.payable = payment.payable
        self.payable = result.payable
        return invalid_payment_amount_failure unless valid_payment_amount?(payment, alipay_payment)
        return result if payment.payable.payment_succeeded?

        payable_payment_status = payment.payment_provider&.determine_payment_status(status)
        payment.status = status
        payment.payable_payment_status = payable_payment_status
        payment.save!

        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)
        update_invoices_paid_amount_cents(payment_status: payable_payment_status)
        reset_customer_dunning_campaign_status(payable_payment_status)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def payment_url_params(out_trade_no)
        {
          out_trade_no:,
          total_amount: format("%.2f", payable.total_amount_cents / 100.0),
          subject: "#{payable.billing_entity.name} - Overdue invoices",
          product_code: CHECKOUT_PRODUCT_CODE,
          passback_params: CGI.escape(passback_params.to_json)
        }
      end

      def passback_params
        {
          lago_payable_id: payable.id,
          lago_payable_type: payable.class.name,
          lago_customer_id: customer.id,
          payment_type: "one-time"
        }
      end

      def create_payment(alipay_payment)
        @payable = PaymentRequest.find_by(id: alipay_payment.metadata["lago_payable_id"])
        return unless payable

        payable.increment_payment_attempts!

        Payment.new(
          organization_id: payable.organization_id,
          payable:,
          customer:,
          payment_provider_id: alipay_payment_provider.id,
          payment_provider_customer_id: customer.alipay_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency,
          provider_payment_id: alipay_payment.id
        )
      end

      def valid_payment_amount?(payment, alipay_payment)
        alipay_payment.amount_cents.present? && payment.amount_cents == alipay_payment.amount_cents
      end

      def invalid_payment_amount_failure
        result.service_failure!(
          code: "invalid_payment_amount",
          message: "Alipay total_amount does not match the Lago payment amount"
        )
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true)
        payable.invoices.each do |invoice|
          next if invoice.payment_succeeded? && payment_status.to_sym != :succeeded

          Invoices::UpdateService.call(
            invoice:,
            params: {
              payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
              ready_for_payment_processing: payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status.to_sym == :succeeded
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign_for_currency!(payable.currency)
      end

      def reusable_provider_payment_id
        payable.payments
          .where(payment_provider_id: alipay_payment_provider.id)
          .where(payable_payment_status: %w[pending processing])
          .where.not(provider_payment_id: nil)
          .order(created_at: :desc)
          .pick(:provider_payment_id)
      end

      def provider_payment_id
        "pr_#{payable.id.delete("-")}_#{SecureRandom.hex(6)}"
      end

      def checkout_session(out_trade_no, params)
        client.page_pay_session(biz_content: params, notify_url:, return_url: success_redirect_url)
          .merge(out_trade_no:)
      end

      def success_redirect_url
        alipay_payment_provider.success_redirect_url.presence || ::PaymentProviders::AlipayProvider::SUCCESS_REDIRECT_URL
      end

      def notify_url
        URI.join(
          ENV["LAGO_API_URL"],
          "webhooks/alipay/#{organization.id}?code=#{URI.encode_www_form_component(alipay_payment_provider.code)}"
        ).to_s
      end

      def client
        @client ||= ::PaymentProviders::Alipay::Client.new(payment_provider: alipay_payment_provider)
      end

      def alipay_payment_provider
        @alipay_payment_provider ||= payment_provider(customer)
      end

    end
  end
end
