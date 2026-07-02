# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::HandleEventService do
  subject(:service) { described_class.new(organization:, event:) }

  let(:organization) { create(:organization) }
  let(:event) do
    {
      "out_trade_no" => "inv_123",
      "trade_status" => "TRADE_SUCCESS",
      "total_amount" => "1.34",
      "passback_params" => CGI.escape(
        {
          lago_payable_id: invoice.id,
          lago_payable_type: "Invoice",
          lago_customer_id: invoice.customer_id,
          payment_type: "one-time"
        }.to_json
      )
    }
  end
  let(:invoice) { create(:invoice, organization:) }

  describe "#call" do
    context "with a payment event" do
      let(:payment_service) { instance_double(Invoices::Payments::AlipayService) }

      before do
        allow(Invoices::Payments::AlipayService).to receive(:new).and_return(payment_service)
        allow(payment_service).to receive(:update_payment_status).and_return(BaseService::Result.new)
      end

      it "updates the Alipay payment status" do
        result = service.call

        expect(result).to be_success
        expect(payment_service).to have_received(:update_payment_status).with(
          organization_id: organization.id,
          status: "TRADE_SUCCESS",
          alipay_payment: have_attributes(
            id: "inv_123",
            status: "TRADE_SUCCESS",
            amount_cents: 134,
            metadata: hash_including("lago_payable_type" => "Invoice")
          )
        )
      end
    end

    context "with a refund event" do
      let(:event) do
        {
          "out_trade_no" => "inv_123",
          "out_biz_no" => "cn_123",
          "refund_fee" => "1.34",
          "passback_params" => CGI.escape(
            {
              lago_payable_id: invoice.id,
              lago_payable_type: "Invoice",
              lago_customer_id: invoice.customer_id,
              payment_type: "one-time"
            }.to_json
          )
        }
      end
      let(:refund_service) { instance_double(CreditNotes::Refunds::AlipayService) }

      before do
        allow(CreditNotes::Refunds::AlipayService).to receive(:new).and_return(refund_service)
        allow(refund_service).to receive(:update_status).and_return(BaseService::Result.new)
      end

      it "updates the Alipay refund status" do
        result = service.call

        expect(result).to be_success
        expect(refund_service).to have_received(:update_status).with(
          provider_refund_id: "cn_123",
          status: "succeeded",
          metadata: hash_including("lago_payable_type" => "Invoice")
        )
      end
    end
  end
end
