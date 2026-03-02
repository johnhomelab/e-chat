class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
    end
  end

  def create_kanban_item(params)
    funnel_id = params[0][:funnel_id]
    funnel_stage = params[0][:funnel_stage]
    return unless funnel_id.present? && funnel_stage.present?

    funnel = @account.funnels.find_by(id: funnel_id)
    return unless funnel

    # Verificar se já existe item para esta conversa
    return if KanbanItem.exists?(conversation_display_id: @conversation.display_id, account_id: @account.id)

    kanban_item = KanbanItem.create!(
      account_id: @account.id,
      funnel_id: funnel.id,
      funnel_stage: funnel_stage,
      position: funnel.kanban_items.count + 1,
      item_details: {
        title: @conversation.contact&.name || 'Sem nome',
        status: 'open',
        description: @conversation.messages.last&.content || '',
        priority: @conversation.priority || 'medium',
        conversation_id: @conversation.display_id,
        custom_attributes: @conversation.custom_attributes || []
      },
      conversation_display_id: @conversation.display_id
    )

    kanban_item.assign_agent(@conversation.assignee_id) if @conversation.assignee_id.present?
  end

  def find_kanban_item
    KanbanItem.find_by(conversation_display_id: @conversation.display_id, account_id: @account.id)
  end

  def move_kanban_item_to_stage(params)
    funnel_id = params[0][:funnel_id]
    funnel_stage = params[0][:funnel_stage]
    return unless funnel_id.present? && funnel_stage.present?

    kanban_item = find_kanban_item
    return unless kanban_item

    funnel = @account.funnels.find_by(id: funnel_id)
    return unless funnel

    kanban_item.funnel_id = funnel.id if kanban_item.funnel_id != funnel.id
    kanban_item.move_to_stage(funnel_stage)
  end

  def assign_agent_to_kanban_item(params)
    agent_id = params[0]
    agent_id = agent_id[:id] if agent_id.is_a?(Hash)
    agent_id = agent_id.to_i if agent_id.present?
    return unless agent_id.present?

    kanban_item = find_kanban_item
    return unless kanban_item

    kanban_item.assign_agent(agent_id)
  end

  def add_note_to_kanban_item(params)
    note_text = params[0]
    return unless note_text.present?

    kanban_item = find_kanban_item
    return unless kanban_item

    kanban_item.add_note(
      text: note_text,
      agent_id: Current.user&.id
    )
  end

  def start_kanban_item_timer(_params)
    kanban_item = find_kanban_item
    return unless kanban_item

    kanban_item.start_timer
  end

  def stop_kanban_item_timer(_params)
    kanban_item = find_kanban_item
    return unless kanban_item

    kanban_item.stop_timer
  end
end
