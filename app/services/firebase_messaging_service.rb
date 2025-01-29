class FirebaseMessagingService
  include Singleton

  FCM_URL = "https://fcm.googleapis.com/v1/projects/%s/messages:send".freeze
  TOKEN_EXPIRY = 3500 # Token typically expires in 1 hour (3600 seconds), refresh 100s earlier
  CLEANUP_PROBABILITY = 0.01 # 1% chance to cleanup on each request

  # FCM best practices constants
  MIN_RETRY_DELAY = 10   # Minimum 10 seconds before first retry
  MAX_RETRY_DELAY = 60   # Maximum delay between retries
  MAX_RETRY_TIME = 3600  # Maximum 1 hour total retry time
  REQUEST_TIMEOUT = 10   # 10 second timeout for FCM requests
  MAX_RETRIES = 5       # Maximum number of retries
  JITTER_RANGE = 0.5    # ±50% jitter

  # Error codes that should not be retried (permanent failures)
  NON_RETRYABLE_ERRORS = {
    "INVALID_ARGUMENT" => "Invalid message format or invalid fields",
    "UNREGISTERED" => "Token is not registered/invalid",
    "SENDER_ID_MISMATCH" => "Token does not match sender ID",
    "THIRD_PARTY_AUTH_ERROR" => "Invalid credentials",
    "INVALID_CREDENTIAL" => "Invalid credentials or project ID"
  }.freeze

  # HTTP status codes and their retry behavior
  RETRY_STRATEGY = {
    400 => :abort,      # Bad Request
    401 => :abort,      # Unauthorized
    403 => :abort,      # Forbidden
    404 => :abort,      # Not Found
    429 => :retry_429,  # Too Many Requests
    500 => :retry,      # Internal Server Error
    502 => :retry,      # Bad Gateway
    503 => :retry,      # Service Unavailable
    504 => :retry       # Gateway Timeout
  }.freeze

  def initialize
    @token_cache = {}
    @cache_mutex = Mutex.new
  end

  def send_message(credentials, message)
    credentials_json = parse_credentials(credentials)
    project_id = credentials_json["project_id"]
    url = FCM_URL % project_id

    start_time = Time.current
    retries = 0

    begin
      response = HTTP.timeout(REQUEST_TIMEOUT)
                    .auth("Bearer #{ensure_fresh_token(credentials_json)}")
                    .headers(accept: "application/json")
                    .post(url, json: message)

      Rails.logger.info("[Firebase Response] Status: #{response.status}, Body: #{response.body}")

      response_body = JSON.parse(response.body.to_s)

      unless response.status.success?
        error = response_body.dig("error", "status") || response_body.dig("error", "message")

        strategy = RETRY_STRATEGY[response.status.to_i] || :retry

        case strategy
        when :abort
          Rails.logger.error("[Firebase] Non-retryable error: #{error}")
          raise "Firebase API error: #{error}"
        when :retry_429
          retry_after = response.headers["retry-after"]&.to_i || 60
          raise RetryableError.new("Rate limited", retry_after)
        when :retry
          if NON_RETRYABLE_ERRORS.key?(error)
            Rails.logger.error("[Firebase] Non-retryable error: #{error} - #{NON_RETRYABLE_ERRORS[error]}")
            raise "Firebase API error: #{error} - #{NON_RETRYABLE_ERRORS[error]}"
          end
          raise RetryableError.new("Firebase API error: #{error}", MIN_RETRY_DELAY)
        end
      end

      response_body
    rescue RetryableError, HTTP::TimeoutError, HTTP::ConnectionError => e
      retry_after = e.respond_to?(:retry_after) ? e.retry_after : calculate_retry_delay(retries)

      # Check if we've exceeded the maximum retry time
      if Time.current - start_time + retry_after > MAX_RETRY_TIME
        Rails.logger.error("[Firebase] Exceeded maximum retry time of #{MAX_RETRY_TIME} seconds")
        raise "Firebase error: Maximum retry time exceeded"
      end

      if retries < MAX_RETRIES
        retries += 1

        # Apply jitter to the retry delay
        jittered_delay = apply_jitter(retry_after)
        Rails.logger.warn("[Firebase] Error encountered, attempt #{retries}/#{MAX_RETRIES}. Retrying in #{jittered_delay.round(2)}s... Error: #{e.message}")

        sleep jittered_delay
        retry
      end

      raise "Firebase error after #{retries} retries: #{e.message}"
    end
  end

  private

  class RetryableError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after = nil)
      super(message)
      @retry_after = retry_after
    end
  end

  def calculate_retry_delay(retry_count)
    # Exponential backoff: MIN_RETRY_DELAY * (2 ^ retry_count)
    delay = MIN_RETRY_DELAY * (2 ** retry_count)
    [ delay, MAX_RETRY_DELAY ].min
  end

  def apply_jitter(delay)
    jitter = delay * JITTER_RANGE * (2 * rand - 1)  # Random value between -JITTER_RANGE and +JITTER_RANGE
    [ delay + jitter, MIN_RETRY_DELAY ].max
  end

  def parse_credentials(credentials)
    return credentials if credentials.is_a?(Hash)

    begin
      JSON.parse(credentials)
    rescue JSON::ParserError => e
      raise "Invalid Firebase credentials format: #{e.message}"
    end
  end

  def ensure_fresh_token(credentials_json)
    cleanup_expired_tokens if rand < CLEANUP_PROBABILITY

    credentials_hash = Digest::SHA256.hexdigest(credentials_json.to_json)
    current_time = Time.current

    @cache_mutex.synchronize do
      cached = @token_cache[credentials_hash]
      if cached && cached[:expires_at] > current_time
        Rails.logger.debug("[Firebase] Using cached token for project: #{cached[:project_id]}")
        return cached[:token]
      end

      generate_and_cache_token(credentials_json, credentials_hash)
    end
  end

  def generate_and_cache_token(credentials_json, credentials_hash)
    auth = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(credentials_json.to_json),
      scope: [ "https://www.googleapis.com/auth/firebase.messaging" ]
    )

    auth.fetch_access_token!
    token = auth.access_token
    expires_at = Time.current + TOKEN_EXPIRY

    Rails.logger.info("[Firebase] Generating new token for project: #{credentials_json['project_id']}")

    @token_cache[credentials_hash] = {
      token: token,
      expires_at: expires_at,
      project_id: credentials_json["project_id"]
    }

    token
  end

  def cleanup_expired_tokens
    current_time = Time.current
    @cache_mutex.synchronize do
      @token_cache.delete_if { |_, data| data[:expires_at] < current_time }
    end
  end
end
