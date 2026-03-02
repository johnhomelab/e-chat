# == Schema Information
#
# Table name: scheduled_messages
#
#  id              :bigint           not null, primary key
#  content         :text             not null
#  is_recurrent    :boolean
#  period          :jsonb
#  scheduled_at    :datetime         not null
#  status          :string           default("pending")
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  inbox_id        :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_scheduled_messages_on_account_id       (account_id)
#  index_scheduled_messages_on_conversation_id  (conversation_id)
#  index_scheduled_messages_on_inbox_id         (inbox_id)
#  index_scheduled_messages_on_scheduled_at     (scheduled_at)
#  index_scheduled_messages_on_status           (status)
#  index_scheduled_messages_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (user_id => users.id)
#
class ScheduledMessage < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :user

  validates :content, presence: true
  validates :scheduled_at, presence: true
  validates :status, presence: true

  enum status: { pending: 'pending', sent: 'sent', failed: 'failed' }, _prefix: true

  after_create :schedule_message
  after_initialize :set_default_status, if: :new_record?
  
  def self.reschedule!(scheduled_message)
    # Reagenda baseado no tipo de período configurado
    period_type = scheduled_message.period&.dig('type') || 'every_day'
    
    next_time = case period_type
                when 'every_day'
                  scheduled_message.scheduled_at + 1.day
                when 'every_day_at_time'
                  # Mantém o mesmo horário, mas no dia seguinte
                  scheduled_message.scheduled_at + 1.day
                when 'every_week'
                  scheduled_message.scheduled_at + 1.week
                when 'every_month'
                  scheduled_message.scheduled_at + 1.month
                when 'every_weekday'
                  # Próximo dia útil (segunda a sexta)
                  next_weekday = scheduled_message.scheduled_at + 1.day
                  while next_weekday.wday == 0 || next_weekday.wday == 6
                    next_weekday += 1.day
                  end
                  next_weekday
                when 'every_weekend'
                  # Próximo fim de semana
                  next_weekend = scheduled_message.scheduled_at + 1.day
                  while next_weekend.wday != 0 && next_weekend.wday != 6
                    next_weekend += 1.day
                  end
                  next_weekend
                else
                  scheduled_message.scheduled_at + 1.day
                end
    
    novo = scheduled_message.dup
    novo.scheduled_at = next_time
    novo.status = 'pending'
    novo.save!
  end

  private

  def schedule_message
    ScheduledMessageJob.set(wait_until: scheduled_at).perform_later(id)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end 
