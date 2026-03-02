json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation

json.kanban_items [@conversation.latest_kanban_item].compact do |kanban_item|
  json.id kanban_item.id
  json.funnel_id kanban_item.funnel_id
  json.funnel_stage kanban_item.funnel_stage
  json.position kanban_item.position
  json.conversation_display_id kanban_item.conversation_display_id
  json.timer_started_at kanban_item.timer_started_at
  json.timer_duration kanban_item.timer_duration
  json.custom_attributes kanban_item.custom_attributes
  json.item_details kanban_item.item_details
  json.funnel do
    json.id kanban_item.funnel.id
    json.name kanban_item.funnel.name
    json.description kanban_item.funnel.description
    json.active kanban_item.funnel.active
    json.stages kanban_item.funnel.stages
    json.settings kanban_item.funnel.settings
  end
end
