class AutoCreateItemJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)

    # Verificação de existência global, antes de qualquer iteração.
    # Garante que um item de Kanban seja criado apenas uma vez por conversa.
    return if ::KanbanItem.exists?(conversation_display_id: conversation.display_id)

    account = conversation.account

    account.funnels.active.each do |funnel|
      next unless funnel.stages.present?

      funnel.stages.each do |stage_id, stage|
        next unless should_create_kanban_item?(conversation, stage)

        create_kanban_item(conversation, funnel, stage_id, stage)
      end
    end
  end

  private

  def should_create_kanban_item?(conversation, stage)
    # Verifica se tem condições de auto_criação
    return false unless stage['auto_create_conditions'].present?

    # Cria uma cópia das condições para não modificar o original
    conditions = stage['auto_create_conditions'].dup

    # Se o stage tem inbox_id configurado, adiciona a condição inbox_matches automaticamente
    if stage['inbox_id'].present?
      conditions << {
        'type' => 'inbox_matches',
        'value' => stage['inbox_id']
      }
    end

    # Avalia as condições (incluindo inbox_matches se configurado)
    evaluate_conditions(conversation, conditions)
  end

  def evaluate_conditions(conversation, conditions)
    return true if conditions.blank?

    contact = conversation.contact

    # Separa condições de inbox (OR) das demais (AND)
    inbox_conditions = conditions.select { |c| c['type'] == 'inbox_matches' }
    other_conditions = conditions.reject { |c| c['type'] == 'inbox_matches' }

    # Inbox: qualquer uma deve ser verdadeira (OR)
    inbox_match = inbox_conditions.empty? || inbox_conditions.any? { |condition| evaluate_condition(conversation, contact, condition) }

    # Outras: todas devem ser verdadeiras (AND)
    other_match = other_conditions.all? { |condition| evaluate_condition(conversation, contact, condition) }

    inbox_match && other_match
  end

  def evaluate_condition(conversation, contact, condition)
    case condition['type']
    when 'contact_has_tag'
      contact_has_tag?(contact, condition['value'])
    when 'contact_has_custom_attribute'
      contact_has_custom_attribute?(contact, condition['attribute'], condition['operator'], condition['value'])
    when 'message_contains'
      message_contains?(conversation, condition['value'])
    when 'conversation_has_priority'
      conversation_has_priority?(conversation, condition['value'])
    when 'inbox_matches'
      inbox_matches?(conversation, condition['value'])
    when 'message_is_private'
      message_is_private?(conversation, condition['value'])
    when 'message_has_automation'
      message_has_automation?(conversation, condition['value'])
    when 'conversation_message_count'
      conversation_message_count?(conversation, condition['operator'], condition['value'].to_i)
    when 'last_message_age'
      last_message_age?(conversation, condition['operator'], condition['value'].to_i)
    when 'message_not_read'
      message_not_read?(conversation)
    when 'conversation_unassigned'
      conversation_unassigned?(conversation)
    when 'conversation_reopened'
      conversation_reopened?(conversation)
    when 'conversation_snoozed'
      conversation_snoozed?(conversation)
    else
      true # Condição desconhecida, não bloqueia
    end
  end

  def contact_has_tag?(contact, tag_name)
    contact.labels.any? { |label| label.name.downcase == tag_name.downcase }
  end

  def contact_has_custom_attribute?(contact, attribute, operator, value)
    contact_value = contact.custom_attributes&.dig(attribute)
    return false if contact_value.blank?

    case operator
    when 'equal_to'
      contact_value.to_s == value.to_s
    when 'contains'
      contact_value.to_s.downcase.include?(value.to_s.downcase)
    when 'not_equal_to'
      contact_value.to_s != value.to_s
    else
      true
    end
  end

  def message_contains?(conversation, text)
    return false if conversation.messages.incoming.empty?

    last_message = conversation.messages.incoming.last
    last_message.content.to_s.downcase.include?(text.to_s.downcase)
  end

  def conversation_has_priority?(conversation, priority)
    conversation.priority == priority
  end

  def inbox_matches?(conversation, inbox_id)
    conversation.inbox_id.to_s == inbox_id.to_s
  end

  def message_is_private?(conversation, text)
    conversation.messages.where(private: true).where('content ILIKE ?', "%#{text}%").exists?
  end

  def message_has_automation?(conversation, text)
    conversation.messages.where("content_attributes ->> 'automation_rule_id' IS NOT NULL")
                     .where('content ILIKE ?', "%#{text}%").exists?
  end

  def conversation_message_count?(conversation, operator, count)
    message_count = conversation.messages.count
    case operator
    when 'equal_to'
      message_count == count
    when 'greater_than'
      message_count > count
    when 'less_than'
      message_count < count
    when 'greater_than_or_equal'
      message_count >= count
    when 'less_than_or_equal'
      message_count <= count
    else
      false
    end
  end

  def last_message_age?(conversation, operator, minutes)
    last_message = conversation.messages.order(created_at: :desc).first
    return false unless last_message

    age_minutes = ((Time.current - last_message.created_at) / 60).to_i
    case operator
    when 'greater_than'
      age_minutes > minutes
    when 'less_than'
      age_minutes < minutes
    when 'equal_to'
      age_minutes == minutes
    else
      false
    end
  end

  def message_not_read?(conversation)
    conversation.messages.where(status: :sent).exists?
  end

  def conversation_unassigned?(conversation)
    conversation.assignee_id.blank?
  end

  def conversation_reopened?(conversation)
    # Considera reaberta se foi resolvida e depois teve mensagens depois da resolução
    return false unless conversation.resolved?

    last_resolved_at = conversation.updated_at
    conversation.messages.where('created_at > ?', last_resolved_at).exists?
  end

  def conversation_snoozed?(conversation)
    conversation.snoozed?
  end

  def create_kanban_item(conversation, funnel, stage_id, stage)
    # A verificação de existência foi movida para o método `perform`, tornando esta verificação redundante.
    # O item será criado apenas se não existir nenhum item para esta conversa em qualquer funil.

    kanban_item = ::KanbanItem.create!(
      account_id: conversation.account.id,
      funnel_id: funnel.id,
      funnel_stage: stage_id,
      position: funnel.kanban_items.count + 1,
      item_details: build_item_details(conversation, stage_id),
      conversation_display_id: conversation.display_id
    )

    # Atribuir o agente da conversa ao item do Kanban
    kanban_item.assign_agent(conversation.assignee_id) if conversation.assignee_id.present?

    kanban_item
  end

  def build_item_details(conversation, stage_id)
    {
      title: conversation.contact&.name || 'Sem nome',
      status: 'open',
      description: '',
      currency: { symbol: 'R$', code: 'BRL', locale: 'pt-BR' },
      priority: conversation.priority || 'none',
      agent_id: conversation.assignee_id,
      conversation_id: conversation.display_id,
      scheduling_type: '',
      offers: [],
      custom_attributes: conversation.custom_attributes || [],
      notes: [
        id: SecureRandom.uuid,
        text: "Esse item foi criado automaticamente pela etapa #{stage_id} baseado nas condições configuradas!",
        created_at: Time.current
      ]
    }
  end
end
