# frozen_string_literal: true

module LagoUtils
  class License
    def initialize(url)
      @url = url
      @premium = false
    end

    def verify
      return if ENV["LAGO_LICENSE"].blank?

      http_client = LagoHttpClient::Client.new("#{url}/verify/#{ENV["LAGO_LICENSE"]}")
      response = http_client.get

      @premium = response["valid"]
    end

    def premium?
      return true if premium_unlock_enabled?

      premium
    end

    def premium_unlock_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["LAGO_UNLOCK_PREMIUM_FEATURES"])
    end

    def data_api_unlock_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["LAGO_UNLOCK_DATA_API_FEATURES"])
    end

    private

    attr_reader :url, :premium
  end
end
