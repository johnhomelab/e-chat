class CreateFunnels < ActiveRecord::Migration[7.0]
  def up
    # Renomeia a tabela existente se ela existir
    if table_exists?(:funnels)
      rename_table :funnels, :funnels_old
    end

    create_table :funnels do |t|
      # Relacionamentos essenciais
      t.references :account, null: false, index: true
      
      # Campos básicos
      t.string :name, null: false
      t.string :description
      t.boolean :active, default: true
      
      # Configurações do funil
      t.jsonb :stages, default: {}, null: false # Armazena as etapas do funil e suas configurações
      t.jsonb :settings, default: {} # Configurações gerais do funil
      
      # Campos de auditoria
      t.timestamps
    end

    # Adiciona índice para busca por nome
    add_index :funnels, [:account_id, :name], unique: true
    
    # Adiciona chave estrangeira para garantir integridade referencial
    add_foreign_key :kanban_items, :funnels
  end

  def down
    remove_foreign_key :kanban_items, :funnels if foreign_key_exists?(:kanban_items, :funnels)
    drop_table :funnels if table_exists?(:funnels)
    
    # Restaura a tabela antiga se ela existir
    if table_exists?(:funnels_old)
      rename_table :funnels_old, :funnels
    end
  end
end 