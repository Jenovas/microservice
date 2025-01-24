class PushResult < ApplicationRecord
  belongs_to :campaign, foreign_key: :campaign_guid, primary_key: :campaign_guid

  validates :campaign_guid, :user_token, :platform, :processed_at, presence: true
  validates :platform, inclusion: { in: %w[android ios] }
  validates :user_token, uniqueness: { scope: :campaign_guid }
  validates :error, presence: true, if: -> { !was_success }

  scope :by_campaign, ->(guid) { where(campaign_guid: guid) }
  scope :successful, -> { where(was_success: true) }
  scope :failed, -> { where(was_success: false) }
  scope :by_platform, ->(platform) { where(platform: platform) }
end
