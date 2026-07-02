# frozen_string_literal: true

module PaymentProviders
  module Alipay
    class Client
      FORMAT = "JSON"
      CHARSET = "utf-8"
      SIGN_TYPE = "RSA2"
      VERSION = "1.0"

      PRODUCTION_GATEWAY_URL = "https://openapi.alipay.com/gateway.do"
      SANDBOX_GATEWAY_URL = "https://openapi-sandbox.dl.alipaydev.com/gateway.do"

      def initialize(payment_provider:)
        @payment_provider = payment_provider
      end

      def page_pay_session(params)
        fields = signed_params(
          method: "alipay.trade.page.pay",
          biz_content: params[:biz_content],
          notify_url: params[:notify_url],
          return_url: params[:return_url]
        )

        {
          gateway_url: gateway_url_with_charset(fields[:charset]),
          fields: fields.except(:charset)
        }
      end

      def refund(params)
        post_api(
          method: "alipay.trade.refund",
          response_key: "alipay_trade_refund_response",
          biz_content: params
        )
      end

      def refund_query(params)
        post_api(
          method: "alipay.trade.fastpay.refund.query",
          response_key: "alipay_trade_fastpay_refund_query_response",
          biz_content: params
        )
      end

      def trade_query(params)
        post_api(
          method: "alipay.trade.query",
          response_key: "alipay_trade_query_response",
          biz_content: params
        )
      end

      def close(params)
        post_api(
          method: "alipay.trade.close",
          response_key: "alipay_trade_close_response",
          biz_content: params
        )
      end

      def bill_download_url(params)
        post_api(
          method: "alipay.data.dataservice.bill.downloadurl.query",
          response_key: "alipay_data_dataservice_bill_downloadurl_query_response",
          biz_content: params
        )
      end

      def valid_notification?(params)
        signature = params["sign"].to_s
        return false if signature.blank?

        verifier.verify(
          OpenSSL::Digest::SHA256.new,
          Base64.decode64(signature),
          notification_canonical_string(params)
        )
      rescue OpenSSL::PKey::RSAError, ArgumentError
        false
      end

      private

      attr_reader :payment_provider

      delegate :app_id, :app_private_key, :alipay_public_key, to: :payment_provider

      def post_api(method:, response_key:, biz_content:)
        response = http_client.post_url_encoded(
          signed_params(method:, biz_content:),
          {}
        )

        response.fetch(response_key, {})
      end

      def gateway_url_with_charset(charset)
        "#{gateway_url}?#{URI.encode_www_form(charset:)}"
      end

      def signed_params(method:, biz_content:, notify_url: nil, return_url: nil)
        params = {
          app_id:,
          method:,
          format: FORMAT,
          charset: CHARSET,
          sign_type: SIGN_TYPE,
          timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
          version: VERSION,
          notify_url:,
          return_url:,
          biz_content: JSON.generate(biz_content)
        }.compact

        params.merge(sign: sign(params))
      end

      def sign(params)
        Base64.strict_encode64(
          signer.sign(OpenSSL::Digest::SHA256.new, canonical_string(params))
        )
      end

      def canonical_string(params)
        params.stringify_keys.sort.map { |key, value| "#{key}=#{value}" }.join("&")
      end

      def notification_canonical_string(params)
        params.stringify_keys
          .except("sign", "sign_type")
          .filter { |key, value| key.present? && value.present? }
          .sort
          .map { |key, value| "#{key}=#{value}" }
          .join("&")
      end

      def signer
        @signer ||= rsa_key(app_private_key, ["PRIVATE KEY", "RSA PRIVATE KEY"])
      end

      def verifier
        @verifier ||= rsa_key(alipay_public_key, ["PUBLIC KEY", "RSA PUBLIC KEY"])
      end

      def rsa_key(value, pem_types)
        value = value.to_s.strip
        return OpenSSL::PKey::RSA.new(value) if value.include?("-----BEGIN")

        pem_types.each do |type|
          return OpenSSL::PKey::RSA.new(pem(value, type))
        rescue OpenSSL::PKey::RSAError
          next
        end

        OpenSSL::PKey::RSA.new(value)
      end

      def pem(value, type)
        value = value.to_s.strip
        body = value.delete("\n").scan(/.{1,64}/).join("\n")
        "-----BEGIN #{type}-----\n#{body}\n-----END #{type}-----"
      end

      def gateway_url
        case ENV["LAGO_ALIPAY_ENVIRONMENT"].to_s.downcase
        when "sandbox"
          SANDBOX_GATEWAY_URL
        when "production"
          PRODUCTION_GATEWAY_URL
        else
          Rails.env.production? ? PRODUCTION_GATEWAY_URL : SANDBOX_GATEWAY_URL
        end
      end

      def http_client
        @http_client ||= LagoHttpClient::Client.new(gateway_url)
      end
    end
  end
end
