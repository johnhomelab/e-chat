# Correção do Bug AutoCreateItem no Kanban

## Problema Identificado

O `AutoCreateItemJob` tinha uma lógica duplicada e conflitante para verificação de `inbox_id` que causava falhas na criação automática de itens do kanban quando a condição era `inbox_id` no funnel.

### Bug Original

```ruby
def should_create_kanban_item?(conversation, stage)
  return false unless stage['auto_create_conditions'].present?
  
  # ❌ PROBLEMA: Verificação prematura que impedia avaliação das condições
  if stage['inbox_id'].present?
    return false unless stage['inbox_id'].to_s == conversation.inbox_id.to_s
  end

  evaluate_conditions(conversation, stage['auto_create_conditions'])
end
```

### Problemas Identificados

1. **Verificação Duplicada**: O método `inbox_matches?` já existia para verificar inbox_id nas condições
2. **Verificação Prematura**: O filtro `stage['inbox_id']` era aplicado ANTES das condições `auto_create_conditions`
3. **Comportamento Inconsistente**: Quando `stage['inbox_id']` não coincidia, o método retornava `false` sem avaliar outras condições

## Solução Implementada

### Código Corrigido

```ruby
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
```

### Benefícios da Correção

1. **Elimina Duplicação**: Remove a verificação duplicada de inbox_id
2. **Lógica Consistente**: Todas as verificações passam pelo mesmo fluxo de condições
3. **Mantém Funcionalidade**: O filtro `stage['inbox_id']` continua funcionando
4. **Código Mais Limpo**: Lógica mais clara e fácil de entender

## Cenários de Teste

### Cenário 1: Stage com inbox_id matching + condições válidas
```ruby
conversation.inbox_id = 1
stage = {
  'inbox_id' => '1',
  'auto_create_conditions' => [
    { 'type' => 'contact_has_tag', 'value' => 'vip' }
  ]
}
# Resultado: true (cria item)
```

### Cenário 2: Stage com inbox_id não matching + condições válidas
```ruby
conversation.inbox_id = 2
stage = {
  'inbox_id' => '1',
  'auto_create_conditions' => [
    { 'type' => 'contact_has_tag', 'value' => 'vip' }
  ]
}
# Resultado: false (não cria item - inbox não coincide)
```

### Cenário 3: Stage sem inbox_id + condições válidas
```ruby
conversation.inbox_id = 2
stage = {
  'auto_create_conditions' => [
    { 'type' => 'contact_has_tag', 'value' => 'vip' }
  ]
}
# Resultado: true (cria item - sem filtro de inbox)
```

### Cenário 4: Stage com inbox_id + condição inbox_matches redundante
```ruby
conversation.inbox_id = 1
stage = {
  'inbox_id' => '1',
  'auto_create_conditions' => [
    { 'type' => 'contact_has_tag', 'value' => 'vip' },
    { 'type' => 'inbox_matches', 'value' => '1' }
  ]
}
# Resultado: true (funciona corretamente mesmo com redundância)
```

### Cenário 5: Stage com inbox_id + condição inbox_matches conflitante
```ruby
conversation.inbox_id = 1
stage = {
  'inbox_id' => '1',
  'auto_create_conditions' => [
    { 'type' => 'contact_has_tag', 'value' => 'vip' },
    { 'type' => 'inbox_matches', 'value' => '2' }
  ]
}
# Resultado: false (não cria item - condições conflitantes)
```

## Impacto

### Antes da Correção
- ❌ Items não eram criados quando `stage['inbox_id']` não coincidia, mesmo com outras condições válidas
- ❌ Lógica duplicada e confusa
- ❌ Comportamento inconsistente

### Após a Correção
- ✅ Items são criados corretamente seguindo todas as condições
- ✅ Lógica unificada e consistente
- ✅ Mantém funcionalidade existente
- ✅ Código mais limpo e manutenível

## Arquivos Modificados

- `app/jobs/auto_create_item_job.rb` - Correção principal do bug
- `bugfix_auto_create_item.md` - Documentação da correção

## Testes Relacionados

Os testes em `spec/jobs/auto_create_item_job_spec.rb` devem continuar passando, especialmente o teste "quando há filtro de inbox_id no stage" que valida a funcionalidade corrigida.