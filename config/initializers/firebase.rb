require 'google/cloud/storage'

module Firebase
  class << self
    attr_accessor :service_account_credentials

    def configure
      service_account_path = ENV.fetch('FIREBASE_SERVICE_ACCOUNT_PATH', Rails.root.join('config', 'firebase-service-account.json'))
      
      if File.exist?(service_account_path)
        @service_account_credentials = JSON.parse(File.read(service_account_path))
        @service_account_credentials['private_key'] = @service_account_credentials['private_key'].gsub('\n', "\n")
      else
        Rails.logger.error("Firebase service account file not found at #{service_account_path}")
        @service_account_credentials = nil
      end
    end

    def configured?
      !@service_account_credentials.nil?
    end

    def project_id
      @service_account_credentials&.fetch('project_id')
    end

    def access_token
      return nil unless configured?

      now = Time.now.to_i
      
      # Cache the token for 50 minutes (tokens are valid for 1 hour)
      if @token.nil? || @token_expires_at.nil? || now > @token_expires_at
        assertion = JWT.encode(
          {
            iss: @service_account_credentials['client_email'],
            scope: 'https://www.googleapis.com/auth/firebase.messaging',
            aud: 'https://oauth2.googleapis.com/token',
            exp: now + 3600,
            iat: now
          },
          OpenSSL::PKey::RSA.new(@service_account_credentials['private_key']),
          'RS256'
        )

        response = HTTP.post(
          'https://oauth2.googleapis.com/token',
          form: {
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: assertion
          }
        )

        data = JSON.parse(response.body.to_s)
        @token = data['access_token']
        @token_expires_at = now + data['expires_in'].to_i - 600 # Refresh 10 minutes before expiry
      end

      @token
    end
  end
end

Firebase.configure 