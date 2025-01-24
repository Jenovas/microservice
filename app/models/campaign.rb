class Campaign < ApplicationRecord
  has_many :push_results, foreign_key: :campaign_guid, primary_key: :campaign_guid

  validates :campaign_guid, presence: true
  validates :token, presence: true
  # Do we include web users also?
  validates :device_type, presence: true, inclusion: { in: %w[android ios] }
  # Do we include other campaign types also? Email, SMS, Journey?
  validates :campaign_type, presence: true, inclusion: { in: %w[push in_app feed] }
  validates :credentials, presence: true
  validates :payload, presence: true

  # What about reoccuring campaigns? Probably this validation is not needed?
  validates :token, uniqueness: { scope: :campaign_guid, message: "has already received this campaign" }

  validate :validate_credentials_format
  validate :validate_payload_format

  scope :by_campaign_guid, ->(guid) { where(campaign_guid: guid) }
  scope :by_device_type, ->(type) { where(device_type: type) }
  scope :by_campaign_type, ->(type) { where(campaign_type: type) }

  VALID_PUSH_ACTIONS = %w[deeplink url open_app].freeze
  VALID_BUTTON_ACTIONS = %w[deeplink url open_app dismiss].freeze

  private

  def validate_credentials_format
    return if credentials.blank?

    # Validate certificate presence
    unless credentials["certificate"].present?
      errors.add(:credentials, "must contain certificate")
      return
    end

    # Validate certificate_password is a string if present
    if credentials["certificate_password"].present? && !credentials["certificate_password"].is_a?(String)
      errors.add(:credentials, "certificate_password must be a string")
    end

    # Validate no extra keys are present
    extra_keys = credentials.keys - %w[certificate certificate_password]
    errors.add(:credentials, "contains invalid keys: #{extra_keys.join(', ')}") if extra_keys.any?
  end

  def validate_payload_format
    return if payload.blank?

    case campaign_type
    when "push"
      validate_push_payload
    when "in_app"
      validate_in_app_payload
    when "feed"
      validate_feed_payload
    end
  end

  def validate_push_payload
    push_payload = CampaignPushPayload.new(payload)
    return if push_payload.valid?

    push_payload.errors.each do |error|
      errors.add(:payload, error.full_message)
    end
  end

  def validate_in_app_payload
    required_fields = %w[title content display_type]
    missing_fields = required_fields - payload.keys
    errors.add(:payload, "missing required fields for in_app: #{missing_fields.join(', ')}") if missing_fields.any?
  end

  def validate_feed_payload
    required_fields = %w[title description category]
    missing_fields = required_fields - payload.keys
    errors.add(:payload, "missing required fields for feed: #{missing_fields.join(', ')}") if missing_fields.any?
  end
end
