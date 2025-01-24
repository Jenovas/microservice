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
  MAX_CONCURRENT_RETRIES = 1000  # Maximum number of messages in retry queue
  THREAD_POOL_SIZE = 20  # Number of threads for sending messages

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
    @retry_queue = []
    @retry_mutex = Mutex.new
    @thread_pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: 5,
      max_threads: THREAD_POOL_SIZE,
      max_queue: MAX_CONCURRENT_RETRIES,
      fallback_policy: :caller_runs
    )
    @retry_scheduler = Concurrent::TimerTask.new(execution_interval: 1) do
      process_retry_queue
    end
    @retry_scheduler.execute
  end

  def retry_stats
    @retry_mutex.synchronize do
      {
        total_retries: @retry_queue.size,
        retries_by_age: retry_count_by_age,
        oldest_retry: @retry_queue.first&.dig(:started_at)&.iso8601,
        newest_retry: @retry_queue.last&.dig(:started_at)&.iso8601
      }
    end
  end

  def cancel_retries(count = nil)
    @retry_mutex.synchronize do
      if count
        removed = @retry_queue.shift(count)
        Rails.logger.info("[Firebase] Cancelled #{removed.size} oldest retries")
        removed.size
      else
        size = @retry_queue.size
        @retry_queue.clear
        Rails.logger.info("[Firebase] Cancelled all #{size} retries")
        size
      end
    end
  end

  def send_message(credentials, message)
    future = Concurrent::Promise.new(executor: @thread_pool) do
      send_message_internal(credentials, message)
    end

    future.on_success do |result|
      Rails.logger.info("[Firebase] Message sent successfully")
    end

    future.on_error do |error|
      Rails.logger.error("[Firebase] Failed to send message: #{error.message}")
    end

    future
  end

  private

  def process_retry_queue
    @retry_mutex.synchronize do
      current_time = Time.current
      retries_to_process = @retry_queue.select { |r| r[:next_retry] <= current_time }

      retries_to_process.each do |retry_item|
        @retry_queue.delete(retry_item)

        # Schedule retry in thread pool
        Concurrent::Promise.new(executor: @thread_pool) do
          credentials_json = parse_credentials(retry_item[:credentials])
          send_message_internal(credentials_json, retry_item[:message], retry_item)
        end.execute
      end
    end
  rescue StandardError => e
    Rails.logger.error("[Firebase] Error processing retry queue: #{e.message}")
  end

  def send_message_internal(credentials, message, retry_info = nil)
    credentials_json = parse_credentials(credentials)
    project_id = credentials_json["project_id"]
    url = FCM_URL % project_id

    start_time = retry_info&.dig(:started_at) || Time.current
    retries = retry_info&.dig(:retry_count) || 0
    retry_id = retry_info&.dig(:id) || SecureRandom.uuid

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
          remove_from_retry_queue(retry_id)
          raise "Firebase API error: #{error}"
        when :retry_429
          retry_after = response.headers["retry-after"]&.to_i || 60
          schedule_retry(retry_id, credentials_json, message, start_time, retries, retry_after)
          return
        when :retry
          if NON_RETRYABLE_ERRORS.key?(error)
            Rails.logger.error("[Firebase] Non-retryable error: #{error} - #{NON_RETRYABLE_ERRORS[error]}")
            remove_from_retry_queue(retry_id)
            raise "Firebase API error: #{error} - #{NON_RETRYABLE_ERRORS[error]}"
          end
          schedule_retry(retry_id, credentials_json, message, start_time, retries, MIN_RETRY_DELAY)
          return
        end
      end

      remove_from_retry_queue(retry_id)
      response_body
    rescue StandardError => e
      handle_error(e, retry_id, credentials_json, message, start_time, retries)
    end
  end

  def schedule_retry(retry_id, credentials, message, start_time, retries, base_delay)
    return if retries >= MAX_RETRIES

    retry_after = calculate_retry_delay(retries)
    retry_after = [ base_delay, retry_after ].max

    # Check maximum retry time
    if Time.current - start_time + retry_after > MAX_RETRY_TIME
      Rails.logger.error("[Firebase] Exceeded maximum retry time of #{MAX_RETRY_TIME} seconds")
      remove_from_retry_queue(retry_id)
      raise "Firebase error: Maximum retry time exceeded"
    end

    # Add to retry queue with jittered delay
    jittered_delay = apply_jitter(retry_after)
    next_retry = Time.current + jittered_delay

    @retry_mutex.synchronize do
      if @retry_queue.size >= MAX_CONCURRENT_RETRIES
        Rails.logger.error("[Firebase] Retry queue full (#{@retry_queue.size} items). Dropping retry attempt.")
        raise "Firebase error: Retry queue full"
      end

      @retry_queue << {
        id: retry_id,
        project_id: credentials["project_id"],
        started_at: start_time,
        retry_count: retries + 1,
        next_retry: next_retry,
        credentials: credentials,
        message: message
      }

      @retry_queue.sort_by! { |r| r[:next_retry] }
    end

    Rails.logger.warn("[Firebase] Scheduled retry #{retries + 1}/#{MAX_RETRIES} for #{retry_after}s (jittered: #{jittered_delay.round(2)}s)")
  end

  def handle_error(error, retry_id, credentials, message, start_time, retries)
    if error.is_a?(RetryableError) || error.is_a?(HTTP::TimeoutError) || error.is_a?(HTTP::ConnectionError)
      retry_after = error.respond_to?(:retry_after) ? error.retry_after : calculate_retry_delay(retries)
      schedule_retry(retry_id, credentials, message, start_time, retries, retry_after)
    else
      remove_from_retry_queue(retry_id)
      raise error
    end
  end

  def remove_from_retry_queue(retry_id)
    @retry_mutex.synchronize do
      @retry_queue.delete_if { |r| r[:id] == retry_id }
    end
  end

  def retry_count_by_age
    now = Time.current
    @retry_queue.group_by do |retry_item|
      age = now - retry_item[:started_at]
      case age
      when 0..60        then "1m"
      when 60..300      then "5m"
      when 300..900     then "15m"
      when 900..1800    then "30m"
      else                   "1h+"
      end
    end.transform_values(&:count)
  end

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
