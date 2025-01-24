class CampaignPushPayload
  include ActiveModel::Validations

  VALID_PUSH_ACTIONS = %w[deeplink url open_app].freeze
  VALID_BUTTON_ACTIONS = %w[deeplink url open_app dismiss].freeze

  attr_reader :payload

  validates_presence_of :push_text, :push_action
  validate :validate_push_action
  validate :validate_rich_media
  validate :validate_buttons

  def initialize(payload)
    @payload = payload || {}
  end

  def push_text
    payload["push_text"]
  end

  def push_action
    payload["push_action"]
  end

  def push_action_url
    payload["push_action_url"]
  end

  def push_rich_media
    payload["push_rich_media"]
  end

  def push_buttons
    payload["push_buttons"]
  end

  private

  def validate_push_action
    return unless push_action.present?

    unless VALID_PUSH_ACTIONS.include?(push_action)
      errors.add(:push_action, "must be one of #{VALID_PUSH_ACTIONS.join(', ')}")
    end

    if %w[deeplink url].include?(push_action)
      unless push_action_url.present?
        errors.add(:push_action_url, "is required when push_action is #{push_action}")
      end
      validate_url_or_deeplink(push_action_url, push_action)
    end
  end

  def validate_rich_media
    return unless push_rich_media.present?
    validate_image_url(push_rich_media)
  end

  def validate_buttons
    return unless push_buttons.present?

    unless push_buttons.is_a?(Array)
      errors.add(:push_buttons, "must be an array")
      return
    end

    push_buttons.each_with_index do |button, index|
      unless button.is_a?(Hash)
        errors.add(:push_buttons, "button at position #{index} must be a hash")
        next
      end

      validate_button(button, index)
    end
  end

  def validate_button(button, index)
    # Validate required button fields
    %w[buttonPosition buttonLabel buttonAction].each do |field|
      unless button[field].present?
        errors.add(:push_buttons, "button at position #{index} missing required field: #{field}")
      end
    end

    # Validate button position is an integer
    if button["buttonPosition"].present? && !button["buttonPosition"].is_a?(Integer)
      errors.add(:push_buttons, "buttonPosition at index #{index} must be an integer")
    end

    validate_button_action(button, index)
  end

  def validate_button_action(button, index)
    return unless button["buttonAction"].present?

    unless VALID_BUTTON_ACTIONS.include?(button["buttonAction"])
      errors.add(:push_buttons, "invalid buttonAction at index #{index}: must be one of #{VALID_BUTTON_ACTIONS.join(', ')}")
    end

    if %w[deeplink url].include?(button["buttonAction"])
      unless button["button_action_url"].present?
        errors.add(:push_buttons, "button_action_url is required for button at index #{index} when buttonAction is #{button['buttonAction']}")
      end
      validate_url_or_deeplink(button["button_action_url"], button["buttonAction"])
    end
  end

  def validate_url_or_deeplink(value, type)
    return unless value.present?

    case type
    when "url"
      unless valid_url?(value)
        errors.add(:base, "invalid URL format: #{value}")
      end
    when "deeplink"
      unless valid_deeplink?(value)
        errors.add(:base, "invalid deeplink format: #{value}")
      end
    end
  end

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def valid_deeplink?(deeplink)
    uri = URI.parse(deeplink)
    uri.scheme.present?
  rescue URI::InvalidURIError
    false
  end

  def valid_image_url?(url)
    valid_url?(url) && url.match?(/\.(jpg|jpeg|png|gif|webp)$/i)
  end

  def validate_image_url(url)
    unless valid_image_url?(url)
      errors.add(:base, "invalid image URL format: #{url}")
    end
  end
end
