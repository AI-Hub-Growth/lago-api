# frozen_string_literal: true

module CreditNotes
  module Refunds
    class AlipayService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Alipay"

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        alipay_result = create_alipay_refund
        return result if result.failure?

        status = refund_status(alipay_result)

        refund = Refund.new(
          organization_id: credit_note.organization_id,
          credit_note:,
          refundable: credit_note,
          reason: :credit_note,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment_provider_customer(customer),
          amount_cents: refund_amount_cents(alipay_result),
          amount_currency: payment.amount_currency,
          status:,
          provider_refund_id: refund_request_id
        )
        refund.save!

        update_credit_note_status(refund.status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        result.refund = refund
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(message: e.error_body, code: e.error_code)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")

        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      end

      def update_status(provider_refund_id:, status:, metadata: {})
        refund = Refund.find_by(provider_refund_id:)
        return handle_missing_refund(metadata) unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        refund.update!(status:)
        update_credit_note_status(status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        if status.to_sym == :failed
          deliver_error_webhook(message: "Payment refund failed", code: nil)
          Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
          result.service_failure!(code: "refund_failed", message: "Refund failed to perform")
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_accessor :credit_note

      delegate :organization, :customer, :invoice, to: :credit_note

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present?
      end

      def payment
        return @payment if defined?(@payment)

        @payment = if credit_note.invoice.payments.succeeded.present?
          credit_note.invoice.payments.succeeded.order(created_at: :desc).first
        else
          Payment.where(payable_type: "PaymentRequest")
            .joins("INNER JOIN invoices_payment_requests ON invoices_payment_requests.payment_request_id = payments.payable_id")
            .joins("INNER JOIN payment_requests ON payment_requests.id = invoices_payment_requests.payment_request_id")
            .where("invoices_payment_requests.invoice_id = ?", credit_note.invoice_id)
            .where(payments: {payable_payment_status: "succeeded"})
            .where(payment_requests: {customer_id: credit_note.customer_id})
            .where(payment_requests: {payment_status: 1}) # 1 is succeeded
            .order("payments.created_at DESC")
            .first
        end
      end

      def create_alipay_refund
        response = client.refund(alipay_refund_params)

        unless response["code"] == "10000"
          deliver_error_webhook(message: response["sub_msg"] || response["msg"], code: response["sub_code"] || response["code"])
          update_credit_note_status(:failed)
          Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")

          result.service_failure!(
            code: response["sub_code"] || response["code"] || "alipay_error",
            message: response["sub_msg"] || response["msg"] || "Alipay refund failed"
          )
        end

        response
      end

      def alipay_refund_params
        {
          out_trade_no: payment.provider_payment_id,
          refund_amount: format("%.2f", credit_note.refund_amount_cents / 100.0),
          refund_reason: refund_reason,
          out_request_no: refund_request_id
        }
      end

      def refund_status(alipay_result)
        return "succeeded" if alipay_result["fund_change"] == "Y"
        return "succeeded" if refund_query_succeeded?

        "pending"
      end

      def refund_query_succeeded?
        response = client.refund_query(
          out_trade_no: payment.provider_payment_id,
          out_request_no: refund_request_id
        )

        response["code"] == "10000" && response["refund_status"] == "REFUND_SUCCESS"
      rescue LagoHttpClient::HttpError
        false
      end

      def refund_amount_cents(alipay_result)
        amount = alipay_result["refund_fee"].presence
        return credit_note.refund_amount_cents if amount.blank?

        Money.from_amount(amount.to_d, payment.amount_currency).cents
      end

      def refund_reason
        credit_note.reason.to_s.humanize.presence || "Credit note refund"
      end

      def refund_request_id
        @refund_request_id ||= "cn_#{credit_note.id.delete("-")}"
      end

      def deliver_error_webhook(message:, code:)
        SendWebhookJob.perform_later(
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: payment_provider_customer(customer)&.provider_customer_id,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def handle_missing_refund(metadata)
        return result unless metadata&.key?(:lago_invoice_id)
        return result unless Invoice.find_by(id: metadata[:lago_invoice_id])

        result.not_found_failure!(resource: "alipay_refund")
      end

      def client
        @client ||= PaymentProviders::Alipay::Client.new(payment_provider: alipay_payment_provider)
      end

      def alipay_payment_provider
        @alipay_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
