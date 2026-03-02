# == Schema Information
#
# Table name: kanban_configs
#
#  id             :bigint           not null, primary key
#  config         :jsonb            not null
#  enabled        :boolean          default(TRUE)
#  webhook_events :jsonb
#  webhook_secret :string
#  webhook_url    :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_kanban_configs_on_account_id      (account_id)
#  index_kanban_configs_on_config          (config) USING gin
#  index_kanban_configs_on_webhook_events  (webhook_events) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class KanbanConfig < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true, uniqueness: true
  validates :webhook_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true

  # Configurações padrão do Kanban
  DEFAULT_CONFIG = {
    title: 'Kanban',
    default_view: 'kanban',
    auto_assignment: false,
    notifications_enabled: false,
    support_email: '',
    support_phone: '',
    support_chat_hours: '',
    support_chat_enabled: false,
    dragbar_enabled: true
  }.freeze

  # Eventos de webhook disponíveis
  AVAILABLE_WEBHOOK_EVENTS = %w[
    kanban.item.created
    kanban.item.updated
    kanban.item.deleted
    kanban.item.stage_changed
    kanban.items.reordered
  ].freeze

  after_initialize :set_defaults, if: :new_record?

  def webhook_enabled?
    enabled && webhook_url.present?
  end

  def webhook_event_enabled?(event)
    webhook_enabled? && webhook_events.include?(event)
  end

  def get_config_value(key)
    config[key.to_s] || DEFAULT_CONFIG[key.to_sym]
  end

  def set_config_value(key, value)
    self.config = config.merge(key.to_s => value)
  end

  def update_webhook_config(url:, secret: nil, events: nil, enabled: true)
    self.webhook_url = url
    self.webhook_secret = secret if secret.present?
    self.webhook_events = events if events.present?
    self.enabled = enabled
  end

  private

  def set_defaults
    self.config ||= DEFAULT_CONFIG
    self.webhook_events ||= []
  end
end
