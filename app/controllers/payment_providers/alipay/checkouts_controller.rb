# frozen_string_literal: true

module PaymentProviders
  module Alipay
    class CheckoutsController < ApplicationController
      def show
        session = checkout_session
        return not_found_error(resource: "alipay_checkout") if session.blank?

        render html: html(session).html_safe
      end

      private

      def checkout_session
        return payment_intent_session if params[:id].present?
        return {} if params[:session].blank?

        JSON.parse(Base64.urlsafe_decode64(params[:session].to_s))
      rescue JSON::ParserError, ArgumentError
        {}
      end

      def payment_intent_session
        payment_intent = PaymentIntent.non_expired.find_by(id: params[:id])
        return {} unless payment_intent&.provider_session_id?

        JSON.parse(payment_intent.provider_session_id)
      rescue JSON::ParserError
        {}
      end

      def html(session)
        fields = session.fetch("fields", {}).to_h
        gateway_url = ERB::Util.html_escape(gateway_url_with_charset(session["gateway_url"].to_s, fields))
        inputs = fields.except("charset", :charset).map do |key, value|
          <<~HTML
            <input type="hidden" name="#{ERB::Util.html_escape(key)}" value="#{ERB::Util.html_escape(value.to_s)}">
          HTML
        end.join

        <<~HTML
          <!doctype html>
          <html lang="zh-CN">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>正在前往支付宝收银台</title>
              <style>
                :root { color-scheme: light; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; }
                body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #ffffff; color: #111827; }
                main { width: min(420px, calc(100vw - 40px)); padding: 24px 0; text-align: center; }
                .mark { width: 36px; height: 3px; margin: 0 auto 24px; background: #1677ff; }
                h1 { margin: 0 0 10px; font-size: 22px; line-height: 30px; font-weight: 600; }
                p { margin: 0 0 24px; color: #64748b; font-size: 14px; line-height: 22px; }
                button { border: 0; border-radius: 6px; padding: 12px 20px; background: #1677ff; color: white; font-size: 14px; font-weight: 600; cursor: pointer; }
                button:focus-visible { outline: 3px solid rgba(22, 119, 255, .28); outline-offset: 3px; }
              </style>
            </head>
            <body>
              <main>
                <div class="mark" aria-hidden="true"></div>
                <h1>正在前往支付宝收银台</h1>
                <p>请稍候，页面将自动跳转。</p>
                <form id="alipay-checkout" action="#{gateway_url}" method="post">
                  #{inputs}
                  <button type="submit">继续支付</button>
                </form>
              </main>
              <script>
                window.setTimeout(function () {
                  document.getElementById('alipay-checkout').submit();
                }, 50);
              </script>
            </body>
          </html>
        HTML
      end

      def gateway_url_with_charset(gateway_url, fields)
        uri = URI.parse(gateway_url)
        query = Rack::Utils.parse_nested_query(uri.query)
        query["charset"] ||= fields["charset"] || fields[:charset] || "utf-8"
        uri.query = URI.encode_www_form(query)
        uri.to_s
      rescue URI::InvalidURIError
        gateway_url
      end
    end
  end
end
