# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::Client do
  subject(:client) { described_class.new(payment_provider:) }

  let(:payment_provider) { create(:alipay_provider) }

  around do |example|
    previous_environment = ENV.fetch("LAGO_ALIPAY_ENVIRONMENT", nil)
    ENV.delete("LAGO_ALIPAY_ENVIRONMENT")

    example.run
  ensure
    if previous_environment.nil?
      ENV.delete("LAGO_ALIPAY_ENVIRONMENT")
    else
      ENV["LAGO_ALIPAY_ENVIRONMENT"] = previous_environment
    end
  end

  describe "#page_pay_session" do
    it "returns gateway form fields for POST submission" do
      canonical_payload = nil

      allow(client).to receive(:sign).and_wrap_original do |method, params|
        canonical_payload = client.send(:canonical_string, params)
        method.call(params)
      end

      session = client.page_pay_session(
        biz_content: {
          out_trade_no: "invoice-1",
          total_amount: "10.00",
          subject: "Invoice 1",
          product_code: "FAST_INSTANT_TRADE_PAY"
        },
        notify_url: "https://example.com/notify",
        return_url: "https://example.com/return"
      )

      expect(session[:gateway_url]).to eq("#{PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL}?charset=utf-8")
      expect(canonical_payload).to include("charset=utf-8")
      expect(session[:fields]).to include(
        method: "alipay.trade.page.pay",
        sign_type: "RSA2"
      )
      expect(session[:fields]).not_to include(:charset)
      expect(session[:fields][:sign]).to be_present
    end

    it "uses the sandbox gateway when LAGO_ALIPAY_ENVIRONMENT is sandbox" do
      ENV["LAGO_ALIPAY_ENVIRONMENT"] = "sandbox"
      allow(Rails.env).to receive(:production?).and_return(true)

      session = client.page_pay_session(
        biz_content: {
          out_trade_no: "invoice-1",
          total_amount: "10.00",
          subject: "Invoice 1",
          product_code: "FAST_INSTANT_TRADE_PAY"
        },
        notify_url: "https://example.com/notify",
        return_url: "https://example.com/return"
      )

      expect(session[:gateway_url]).to eq("#{PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL}?charset=utf-8")
    end

    it "uses the production gateway when LAGO_ALIPAY_ENVIRONMENT is production" do
      ENV["LAGO_ALIPAY_ENVIRONMENT"] = "production"

      session = client.page_pay_session(
        biz_content: {
          out_trade_no: "invoice-1",
          total_amount: "10.00",
          subject: "Invoice 1",
          product_code: "FAST_INSTANT_TRADE_PAY"
        },
        notify_url: "https://example.com/notify",
        return_url: "https://example.com/return"
      )

      expect(session[:gateway_url]).to eq("#{PaymentProviders::Alipay::Client::PRODUCTION_GATEWAY_URL}?charset=utf-8")
    end
  end

  describe "#valid_notification?" do
    let(:alipay_private_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:payment_provider) do
      create(
        :alipay_provider,
        app_id: "9021000158636207",
        alipay_public_key: alipay_private_key.public_key.to_pem
      )
    end

    it "verifies notifications using the posted form values" do
      params = {
        "app_id" => payment_provider.app_id,
        "charset" => "utf-8",
        "notify_type" => "trade_status_sync",
        "out_trade_no" => "inv_123",
        "passback_params" => "%7B%22lago_payable_id%22%3A%22invoice-1%22%7D",
        "subject" => "Qiniu - Invoice QIN-1",
        "total_amount" => "9.68",
        "trade_status" => "TRADE_SUCCESS",
        "version" => "1.0"
      }
      canonical_payload = params.sort.map { |key, value| "#{key}=#{value}" }.join("&")
      params["sign"] = Base64.strict_encode64(
        alipay_private_key.sign(OpenSSL::Digest::SHA256.new, canonical_payload)
      )
      params["sign_type"] = "RSA2"

      expect(client.valid_notification?(params)).to be(true)
    end

    it "ignores sign type and blank values like AlipaySignature.rsaCheckV1" do
      params = {
        "app_id" => payment_provider.app_id,
        "charset" => "utf-8",
        "empty_value" => "",
        "subject" => "Qiniu - Invoice",
        "total_amount" => "9.68",
        "trade_status" => "TRADE_SUCCESS",
        "version" => "1.0"
      }
      canonical_payload = params.except("empty_value").sort.map { |key, value| "#{key}=#{value}" }.join("&")
      params["sign"] = Base64.strict_encode64(
        alipay_private_key.sign(OpenSSL::Digest::SHA256.new, canonical_payload)
      )
      params["sign_type"] = "RSA2"

      expect(client.valid_notification?(params)).to be(true)
    end
  end

  describe "#refund" do
    let(:http_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL)
        .and_return(http_client)
      allow(http_client).to receive(:post_url_encoded)
        .and_return(
          "alipay_trade_refund_response" => {
            "code" => "10000",
            "msg" => "Success",
            "fund_change" => "Y",
            "refund_fee" => "10.00"
          }
        )
    end

    it "posts a signed refund request to the Alipay gateway" do
      response = client.refund(
        out_trade_no: "inv_123",
        refund_amount: "10.00",
        refund_reason: "Credit note refund",
        out_request_no: "cn_123"
      )

      expect(response["code"]).to eq("10000")
      expect(http_client).to have_received(:post_url_encoded).with(
        hash_including(
          method: "alipay.trade.refund",
          sign_type: "RSA2",
          charset: "utf-8",
          sign: be_present
        ),
        {}
      )
    end
  end

  describe "#refund_query" do
    let(:http_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL)
        .and_return(http_client)
      allow(http_client).to receive(:post_url_encoded)
        .and_return(
          "alipay_trade_fastpay_refund_query_response" => {
            "code" => "10000",
            "refund_status" => "REFUND_SUCCESS"
          }
        )
    end

    it "posts a signed refund query request to the Alipay gateway" do
      response = client.refund_query(
        out_trade_no: "inv_123",
        out_request_no: "cn_123"
      )

      expect(response["refund_status"]).to eq("REFUND_SUCCESS")
      expect(http_client).to have_received(:post_url_encoded).with(
        hash_including(
          method: "alipay.trade.fastpay.refund.query",
          sign_type: "RSA2",
          charset: "utf-8",
          sign: be_present
        ),
        {}
      )
    end
  end

  describe "#trade_query" do
    let(:http_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL)
        .and_return(http_client)
      allow(http_client).to receive(:post_url_encoded)
        .and_return(
          "alipay_trade_query_response" => {
            "code" => "10000",
            "trade_status" => "TRADE_SUCCESS"
          }
        )
    end

    it "posts a signed trade query request to the Alipay gateway" do
      response = client.trade_query(out_trade_no: "inv_123")

      expect(response["trade_status"]).to eq("TRADE_SUCCESS")
      expect(http_client).to have_received(:post_url_encoded).with(
        hash_including(
          method: "alipay.trade.query",
          sign_type: "RSA2",
          charset: "utf-8",
          sign: be_present
        ),
        {}
      )
    end
  end

  describe "#close" do
    let(:http_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL)
        .and_return(http_client)
      allow(http_client).to receive(:post_url_encoded)
        .and_return(
          "alipay_trade_close_response" => {
            "code" => "10000",
            "msg" => "Success"
          }
        )
    end

    it "posts a signed trade close request to the Alipay gateway" do
      response = client.close(out_trade_no: "inv_123")

      expect(response["code"]).to eq("10000")
      expect(http_client).to have_received(:post_url_encoded).with(
        hash_including(
          method: "alipay.trade.close",
          sign_type: "RSA2",
          charset: "utf-8",
          sign: be_present
        ),
        {}
      )
    end
  end

  describe "#bill_download_url" do
    let(:http_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL)
        .and_return(http_client)
      allow(http_client).to receive(:post_url_encoded)
        .and_return(
          "alipay_data_dataservice_bill_downloadurl_query_response" => {
            "code" => "10000",
            "bill_download_url" => "https://example.com/bill.csv"
          }
        )
    end

    it "posts a signed bill download URL request to the Alipay gateway" do
      response = client.bill_download_url(bill_type: "trade", bill_date: "2026-07-01")

      expect(response["bill_download_url"]).to eq("https://example.com/bill.csv")
      expect(http_client).to have_received(:post_url_encoded).with(
        hash_including(
          method: "alipay.data.dataservice.bill.downloadurl.query",
          sign_type: "RSA2",
          charset: "utf-8",
          sign: be_present
        ),
        {}
      )
    end
  end
end
