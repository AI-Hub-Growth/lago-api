# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::AlipayService do
  subject(:alipay_service) { described_class.new(credit_note) }

  let(:code) { "alipay_1" }
  let(:customer) do
    create(
      :customer,
      payment_provider: "alipay",
      payment_provider_code: code,
      currency: "CNY"
    )
  end
  let(:organization) { customer.organization }
  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      currency: "CNY",
      payment_status: :succeeded,
      total_paid_amount_cents: 200
    )
  end
  let(:alipay_payment_provider) { create(:alipay_provider, organization:, code:) }
  let(:alipay_customer) do
    create(
      :alipay_customer,
      customer:,
      organization:,
      payment_provider: alipay_payment_provider
    )
  end
  let(:client) { instance_double(PaymentProviders::Alipay::Client) }
  let(:payment) do
    create(
      :payment,
      payment_provider: alipay_payment_provider,
      payment_provider_customer: alipay_customer,
      amount_cents: 200,
      amount_currency: "CNY",
      payable_payment_status: "succeeded",
      payable: credit_note.invoice,
      provider_payment_id: "inv_123"
    )
  end
  let(:credit_note) do
    create(
      :credit_note,
      customer:,
      invoice:,
      refund_amount_cents: 134,
      refund_amount_currency: "CNY",
      refund_status: :pending
    )
  end
  let(:refund_response) do
    {
      "code" => "10000",
      "msg" => "Success",
      "fund_change" => "Y",
      "refund_fee" => "1.34",
      "out_trade_no" => "inv_123",
      "trade_no" => "2026070122000000000000"
    }
  end

  describe "#create" do
    before do
      payment

      allow(PaymentProviders::Alipay::Client).to receive(:new)
        .with(payment_provider: alipay_payment_provider)
        .and_return(client)
      allow(client).to receive(:refund)
        .and_return(refund_response)
      allow(client).to receive(:refund_query)
        .and_return({"code" => "10000", "refund_status" => "REFUND_SUCCESS"})
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it "creates an Alipay refund and marks the credit note as succeeded" do
      result = alipay_service.create

      expect(result).to be_success
      expect(client).to have_received(:refund).with(
        out_trade_no: "inv_123",
        refund_amount: "1.34",
        refund_reason: "Duplicated charge",
        out_request_no: "cn_#{credit_note.id.delete("-")}"
      )

      expect(result.refund.id).to be_present
      expect(result.refund.credit_note).to eq(credit_note)
      expect(result.refund.refundable).to eq(credit_note)
      expect(result.refund.reason).to eq("credit_note")
      expect(result.refund.payment).to eq(payment)
      expect(result.refund.payment_provider).to eq(alipay_payment_provider)
      expect(result.refund.payment_provider_customer).to eq(alipay_customer)
      expect(result.refund.amount_cents).to eq(134)
      expect(result.refund.amount_currency).to eq("CNY")
      expect(result.refund.status).to eq("succeeded")
      expect(result.refund.provider_refund_id).to eq("cn_#{credit_note.id.delete("-")}")

      expect(result.credit_note).to be_succeeded
      expect(result.credit_note.refunded_at).to be_present
    end

    it "calls SegmentTrackJob" do
      alipay_service.create

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "refund_status_changed",
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          refund_status: "succeeded"
        }
      )
    end

    context "when the refund response does not confirm a fund change" do
      let(:refund_response) do
        {
          "code" => "10000",
          "msg" => "Success",
          "fund_change" => "N",
          "refund_fee" => "1.34"
        }
      end

      it "confirms the refund through the Alipay refund query API" do
        result = alipay_service.create

        expect(result).to be_success
        expect(client).to have_received(:refund_query).with(
          out_trade_no: "inv_123",
          out_request_no: "cn_#{credit_note.id.delete("-")}"
        )
        expect(result.refund.status).to eq("succeeded")
        expect(result.credit_note).to be_succeeded
      end
    end

    context "when the refund query does not confirm success" do
      let(:refund_response) do
        {
          "code" => "10000",
          "msg" => "Success",
          "fund_change" => "N",
          "refund_fee" => "1.34"
        }
      end

      before do
        allow(client).to receive(:refund_query)
          .and_return({"code" => "10000"})
      end

      it "keeps the refund pending" do
        result = alipay_service.create

        expect(result).to be_success
        expect(result.refund.status).to eq("pending")
        expect(result.credit_note).to be_pending
        expect(result.credit_note.refunded_at).not_to be_present
      end
    end

    context "with an error on Alipay" do
      let(:refund_response) do
        {
          "code" => "40004",
          "msg" => "Business Failed",
          "sub_code" => "ACQ.TRADE_NOT_EXIST",
          "sub_msg" => "交易不存在"
        }
      end

      it "delivers an error webhook" do
        result = alipay_service.create

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("ACQ.TRADE_NOT_EXIST")
        expect(SendWebhookJob).to have_been_enqueued.with(
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: alipay_customer.provider_customer_id,
          provider_error: {
            message: "交易不存在",
            error_code: "ACQ.TRADE_NOT_EXIST"
          }
        )
      end

      it "produces an activity log" do
        alipay_service.create

        expect(Utils::ActivityLog).to have_produced("credit_note.refund_failure").with(credit_note)
      end
    end

    context "when credit note does not have a refund amount" do
      let(:credit_note) do
        create(
          :credit_note,
          customer:,
          refund_amount_cents: 0,
          refund_amount_currency: "CNY"
        )
      end

      it "does not create a refund" do
        result = alipay_service.create

        expect(result).to be_success
        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil
        expect(client).not_to have_received(:refund)
      end
    end

    context "when invoice does not have a payment" do
      let(:payment) { nil }

      it "does not create a refund" do
        result = alipay_service.create

        expect(result).to be_success
        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil
        expect(client).not_to have_received(:refund)
      end
    end

    context "when dispute was lost" do
      let(:invoice) { create(:invoice, :dispute_lost, customer:, organization:) }

      it "does not create a refund" do
        result = alipay_service.create

        expect(result).to be_success
        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil
        expect(client).not_to have_received(:refund)
      end
    end
  end

  describe "#update_status" do
    let(:refund) do
      create(
        :refund,
        credit_note:,
        payment:,
        payment_provider: alipay_payment_provider,
        payment_provider_customer: alipay_customer,
        provider_refund_id: "cn_#{credit_note.id.delete("-")}"
      )
    end

    before do
      refund
      credit_note.pending!
    end

    it "updates the refund status" do
      result = described_class.new.update_status(
        provider_refund_id: refund.provider_refund_id,
        status: "succeeded"
      )

      expect(result).to be_success
      expect(result.refund).to eq(refund)
      expect(result.refund.status).to eq("succeeded")
      expect(result.credit_note).to be_succeeded
      expect(result.credit_note.refunded_at).to be_present
    end
  end
end
