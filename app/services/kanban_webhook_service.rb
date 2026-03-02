class KanbanWebhookService
  def initialize(account)
    @account = account
  end

  def notify_item_created(item)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.created')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.created')
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_created')
  end

  def notify_item_updated(item, changes = {})
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.updated')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.updated', changes: changes)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_updated')
  end

  def notify_item_deleted(item)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.deleted')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.deleted')
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_deleted')
  end

  def notify_stage_change(item, from_stage, to_stage)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.stage_changed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.stage_changed',
                            from_stage: from_stage, to_stage: to_stage)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'stage_changed')
  end

  def notify_item_reordered(items, changes)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.items.reordered')

    webhook_url = get_webhook_url
    payload = build_payload(items, 'kanban.items.reordered', changes: changes)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'items_reordered')
  end

  # Eventos de agente
  def notify_agent_assigned(item, agent_id, agent_data = {})
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.agent.assigned')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.agent.assigned', agent_id: agent_id, agent_data: agent_data)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'agent_assigned')
  end

  def notify_agent_removed(item, agent_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.agent.removed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.agent.removed', agent_id: agent_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'agent_removed')
  end

  # Eventos de notas
  def notify_note_created(item, note_data)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.note.created')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.note.created', note: note_data)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'note_created')
  end

  def notify_note_updated(item, note_id, note_data)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.note.updated')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.note.updated', note_id: note_id, note: note_data)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'note_updated')
  end

  def notify_note_deleted(item, note_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.note.deleted')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.note.deleted', note_id: note_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'note_deleted')
  end

  # Eventos de checklist
  def notify_checklist_item_created(item, checklist_item_data)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.created')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.created', checklist_item: checklist_item_data)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_created')
  end

  def notify_checklist_item_updated(item, checklist_item_id, checklist_item_data)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.updated')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.updated', checklist_item_id: checklist_item_id, checklist_item: checklist_item_data)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_updated')
  end

  def notify_checklist_item_deleted(item, checklist_item_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.deleted')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.deleted', checklist_item_id: checklist_item_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_deleted')
  end

  def notify_checklist_item_toggled(item, checklist_item_id, completed)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.toggled')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.toggled', checklist_item_id: checklist_item_id, completed: completed)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_toggled')
  end

  def notify_checklist_item_completed(item, checklist_item_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.completed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.completed', checklist_item_id: checklist_item_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_completed')
  end

  def notify_checklist_duplicated(item, source_item_id, duplicated_items_count)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.duplicated')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.duplicated', source_item_id: source_item_id, duplicated_items_count: duplicated_items_count)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_duplicated')
  end

  # Eventos de timer
  def notify_timer_started(item)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.timer.started')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.timer.started')
    KanbanWebhookJob.perform_later(webhook_url, payload, 'timer_started')
  end

  def notify_timer_stopped(item, duration)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.timer.stopped')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.timer.stopped', duration: duration)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'timer_stopped')
  end

  # Eventos de status
  def notify_status_changed(item, old_status, new_status)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.status.changed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.status.changed', old_status: old_status, new_status: new_status)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'status_changed')
  end

  # Eventos em massa
  def notify_bulk_moved(items, new_stage)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.items.bulk.moved')

    webhook_url = get_webhook_url
    payload = build_payload(items, 'kanban.items.bulk.moved', new_stage: new_stage, items_count: items.length)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'bulk_moved')
  end

  def notify_bulk_assigned(items, agent_id, agent_data = {})
    return unless webhook_enabled? && webhook_event_enabled?('kanban.items.bulk.assigned')

    webhook_url = get_webhook_url
    payload = build_payload(items, 'kanban.items.bulk.assigned', agent_id: agent_id, agent_data: agent_data, items_count: items.length)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'bulk_assigned')
  end

  def notify_bulk_priority_changed(items, priority)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.items.bulk.priority_changed')

    webhook_url = get_webhook_url
    payload = build_payload(items, 'kanban.items.bulk.priority_changed', priority: priority, items_count: items.length)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'bulk_priority_changed')
  end

  # Eventos de checklist (agente)
  def notify_checklist_item_agent_assigned(item, checklist_item_id, agent_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.agent.assigned')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.agent.assigned', checklist_item_id: checklist_item_id, agent_id: agent_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_agent_assigned')
  end

  def notify_checklist_item_agent_removed(item, checklist_item_id, agent_id)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.checklist.item.agent.removed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.checklist.item.agent.removed', checklist_item_id: checklist_item_id, agent_id: agent_id)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'checklist_item_agent_removed')
  end

  private

  def get_webhook_url
    # Buscar URL do webhook das configurações da conta
    @account.kanban_config&.webhook_url
  end

  def webhook_enabled?
    @account.kanban_config&.webhook_enabled? || false
  end

  def webhook_event_enabled?(event)
    return false unless webhook_enabled?
    return false unless @account.kanban_config&.webhook_events&.include?(event)

    true
  end

  def build_payload(item, event, additional_data = {})
    base_payload = {
      event: event,
      data: {
        item: format_item_data(item),
        timestamp: Time.current,
        account_id: @account.id,
        account_name: @account.name
      }
    }

    # Adicionar dados específicos do evento
    base_payload[:data].merge!(additional_data) if additional_data.present?

    base_payload
  end

  def format_item_data(item)
    if item.is_a?(Array)
      item.map { |i| format_single_item(i) }
    else
      format_single_item(item)
    end
  end

  def format_single_item(item)
    {
      id: item.id,
      account_id: item.account_id,
      conversation_display_id: item.conversation_display_id,
      funnel_id: item.funnel_id,
      funnel_stage: item.funnel_stage,
      stage_entered_at: item.stage_entered_at,
      position: item.position,
      custom_attributes: item.custom_attributes || {},
      item_details: item.item_details || {},
      timer_started_at: item.timer_started_at,
      timer_duration: item.timer_duration,
      assigned_agents: item.assigned_agents || [],
      checklist: item.checklist || [],
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end
end
