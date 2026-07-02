# frozen_string_literal: true

module Invoices
  module Payments
    class AlipayService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Alipay"
      CHECKOUT_PRODUCT_CODE = "FAST_INSTANT_TRADE_PAY"

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def generate_payment_url(payment_intent)
        return result.single_validation_failure!(error_code: "unsupported_currency") unless invoice.currency&.casecmp?("CNY")

        out_trade_no = reusable_provider_payment_id || provider_payment_id("invoice", invoice.id)
        params = payment_url_params(out_trade_no)

        result.provider_session_id = checkout_session(out_trade_no, params).to_json
        result.payment_url = alipay_payment_provider.checkout_payment_url(payment_intent)

        result
      rescue LagoHttpClient::HttpError => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      end

      def expire_payment_url(_payment_intent)
        result
      end

      def update_payment_status(organization_id:, status:, alipay_payment:)
        payment = Payment.find_or_initialize_by(provider_payment_id: alipay_payment.id)
        payment = create_payment(alipay_payment) unless payment.persisted?
        return result.not_found_failure!(resource: "alipay_payment") unless payment

        result.payment = payment
        result.invoice = payment.payable
        self.invoice = result.invoice
        return invalid_payment_amount_failure unless valid_payment_amount?(payment, alipay_payment)
        return result if payment.payable.payment_succeeded?

        payable_payment_status = payment.payment_provider&.determine_payment_status(status)
        payment.status = status
        payment.payable_payment_status = payable_payment_status
        payment.save!

        deliver_webhook if payable_payment_status.to_sym == :succeeded
        update_invoice_payment_status(payment_status: payable_payment_status)

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def payment_url_params(out_trade_no)
        {
          out_trade_no:,
          total_amount: format("%.2f", invoice.total_due_amount_cents / 100.0),
          subject: "#{invoice.billing_entity.name} - Invoice #{invoice.number || invoice.id}",
          product_code: CHECKOUT_PRODUCT_CODE,
          passback_params: CGI.escape(passback_params.to_json)
        }
      end

      def passback_params
        {
          lago_payable_id: invoice.id,
          lago_payable_type: invoice.class.name,
          lago_customer_id: customer.id,
          payment_type: "one-time"
        }
      end

      def create_payment(alipay_payment)
        @invoice = Invoice.find_by(id: alipay_payment.metadata["lago_payable_id"])
        return unless invoice

        invoice.update!(payment_attempts: invoice.payment_attempts + 1)

        Payment.new(
          organization_id: invoice.organization_id,
          payable: invoice,
          customer:,
          payment_provider_id: alipay_payment_provider.id,
          payment_provider_customer_id: customer.alipay_customer.id,
          amount_cents: invoice.total_due_amount_cents,
          amount_currency: invoice.currency,
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

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
        params = {
          payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
          ready_for_payment_processing: payment_status.to_sym != :succeeded
        }

        if payment_status.to_sym == :succeeded
          params[:total_paid_amount_cents] = invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
        end

        Invoices::UpdateService.call!(
          invoice: result.invoice,
          params:,
          webhook_notification: deliver_webhook
        )
      end

      def deliver_webhook
        SendWebhookJob.perform_later("payment.succeeded", result.payment)
      end

      def reusable_provider_payment_id
        invoice.payments
          .where(payment_provider_id: alipay_payment_provider.id)
          .where(payable_payment_status: %w[pending processing])
          .where.not(provider_payment_id: nil)
          .order(created_at: :desc)
          .pick(:provider_payment_id)
      end

      def provider_payment_id(prefix, id)
        "#{prefix.to_s.first(3)}_#{id.delete("-")}_#{SecureRandom.hex(6)}"
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
