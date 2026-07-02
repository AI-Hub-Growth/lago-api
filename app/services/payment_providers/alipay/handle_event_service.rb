# frozen_string_literal: true

module PaymentProviders
  module Alipay
    class HandleEventService < BaseService
      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::AlipayService,
        "PaymentRequest" => PaymentRequests::Payments::AlipayService
      }.freeze

      def initialize(organization:, event:)
        @organization = organization
        @event = event.stringify_keys

        super
      end

      def call
        return handle_refund_event if refund_event?
        return result unless provider_payment_id
        return result unless payment_service_class

        payment_service_class.new.update_payment_status(
          organization_id: organization.id,
          status: event["trade_status"],
          alipay_payment: PaymentProviders::AlipayProvider::AlipayPayment.new(
            id: provider_payment_id,
            status: event["trade_status"],
            amount_cents: amount_cents,
            metadata:
          )
        ).raise_if_error!

        result
      end

      private

      attr_reader :organization, :event

      def handle_refund_event
        CreditNotes::Refunds::AlipayService
          .new
          .update_status(
            provider_refund_id: refund_request_id,
            status: "succeeded",
            metadata:
          ).raise_if_error!

        result
      end

      def refund_event?
        event["refund_fee"].present? && refund_request_id.present?
      end

      def refund_request_id
        event["out_request_no"].presence || event["out_biz_no"].presence
      end

      def payment_service_class
        PAYMENT_SERVICE_CLASS_MAP.fetch(metadata["lago_payable_type"], nil)
      end

      def provider_payment_id
        event["out_trade_no"]
      end

      def amount_cents
        return nil if event["total_amount"].blank?

        Money.from_amount(event["total_amount"].to_d, event["currency"].presence || "CNY").cents
      end

      def metadata
        @metadata ||= begin
          raw = event["passback_params"].to_s
          JSON.parse(CGI.unescape(raw.presence || "{}"))
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
