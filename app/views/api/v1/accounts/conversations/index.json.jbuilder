json.data do
  json.meta do
    json.mine_count @conversations_count[:mine_count]
    json.assigned_count @conversations_count[:assigned_count]
    json.unassigned_count @conversations_count[:unassigned_count]
    json.all_count @conversations_count[:all_count]
  end
  json.payload do
    json.array! @conversations do |conversation|
      json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation
      json.kanban_items [conversation.latest_kanban_item].compact do |kanban_item|
        json.id kanban_item.id
        json.funnel_id kanban_item.funnel_id
        json.funnel_stage kanban_item.funnel_stage
        json.position kanban_item.position
        json.conversation_display_id kanban_item.conversation_display_id
        json.timer_started_at kanban_item.timer_started_at
        json.timer_duration kanban_item.timer_duration
        json.stage_entered_at kanban_item.stage_entered_at
        json.custom_attributes kanban_item.custom_attributes
        json.assigned_agents kanban_item.assigned_agents
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
    end
  end
end
