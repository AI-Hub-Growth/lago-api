# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::Payments::SyncPendingService do
  subject(:service_call) { described_class.call }

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:alipay_provider, organization:) }
  let(:customer) { create(:customer, organization:, payment_provider: "alipay", payment_provider_code: payment_provider.code) }
  let(:provider_customer) { create(:alipay_customer, payment_provider:, customer:, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, currency: "CNY", total_amount_cents: 200_00) }
  let(:client) { instance_double(PaymentProviders::Alipay::Client) }

  before do
    provider_customer
    allow(PaymentProviders::Alipay::Client).to receive(:new)
      .with(payment_provider:)
      .and_return(client)
  end

  context "when a pending Alipay payment succeeds on query" do
    let!(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_cents: 200_00,
        amount_currency: "CNY",
        provider_payment_id: "inv_existing",
        status: "WAIT_BUYER_PAY",
        payable_payment_status: "processing"
      )
    end

    before do
      allow(client).to receive(:trade_query)
        .with(out_trade_no: "inv_existing")
        .and_return(
          "code" => "10000",
          "out_trade_no" => "inv_existing",
          "trade_status" => "TRADE_SUCCESS",
          "total_amount" => "200.00"
        )
    end

    it "updates the Lago payment and invoice status" do
      result = service_call

      expect(result).to be_success
      expect(result.synced_count).to eq(1)
      expect(result.skipped_count).to eq(0)
      expect(payment.reload.status).to eq("TRADE_SUCCESS")
      expect(payment.payable_payment_status).to eq("succeeded")
      expect(invoice.reload).to be_payment_succeeded
    end
  end

  context "when Alipay does not know the trade yet" do
    let!(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_cents: 200_00,
        amount_currency: "CNY",
        provider_payment_id: "inv_missing",
        status: "WAIT_BUYER_PAY",
        payable_payment_status: "processing"
      )
    end

    before do
      allow(client).to receive(:trade_query)
        .with(out_trade_no: "inv_missing")
        .and_return(
          "code" => "40004",
          "sub_code" => "ACQ.TRADE_NOT_EXIST",
          "sub_msg" => "Trade does not exist"
        )
    end

    it "leaves the Lago payment untouched" do
      result = service_call

      expect(result).to be_success
      expect(result.synced_count).to eq(0)
      expect(result.skipped_count).to eq(1)
      expect(payment.reload.status).to eq("WAIT_BUYER_PAY")
      expect(payment.payable_payment_status).to eq("processing")
      expect(invoice.reload).to be_payment_pending
    end
  end

  context "when a pending Alipay payment request payment succeeds on query" do
    let(:payment_request) do
      create(
        :payment_request,
        customer:,
        organization:,
        amount_cents: 200_00,
        amount_currency: "CNY"
      )
    end

    let!(:payment) do
      create(
        :payment,
        payable: payment_request,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_cents: 200_00,
        amount_currency: "CNY",
        provider_payment_id: "pr_existing",
        status: "WAIT_BUYER_PAY",
        payable_payment_status: "processing"
      )
    end

    before do
      allow(client).to receive(:trade_query)
        .with(out_trade_no: "pr_existing")
        .and_return(
          "code" => "10000",
          "out_trade_no" => "pr_existing",
          "trade_status" => "TRADE_SUCCESS",
          "total_amount" => "200.00"
        )
    end

    it "updates the Lago payment request status" do
      result = service_call

      expect(result).to be_success
      expect(result.synced_count).to eq(1)
      expect(payment.reload.status).to eq("TRADE_SUCCESS")
      expect(payment.payable_payment_status).to eq("succeeded")
      expect(payment_request.reload).to be_payment_succeeded
    end
  end
end
