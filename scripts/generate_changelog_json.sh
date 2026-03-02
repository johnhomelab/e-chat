#!/bin/bash

# Script para extrair informações do CHANGELOG.md e gerar JSON para webhook

# Executa o comando changelog se os argumentos foram fornecidos
if [ $# -eq 2 ]; then
    VERSION_ARG="$1"
    IMAGE_NAME="$2"
    # Executa o comando changelog e redireciona a saída para /dev/null
    /Users/macbookpro/Documents/develop/scripts/changelog "$VERSION_ARG" "$IMAGE_NAME" > /dev/null 2>&1
    # Aguarda um pouco para garantir que o arquivo foi escrito
    sleep 2
fi

# Verifica se o CHANGELOG.md existe
if [ ! -f "CHANGELOG.md" ]; then
    echo "Erro: CHANGELOG.md não encontrado"
    exit 1
fi

# Extrai a versão do CHANGELOG.md
VERSION=$(grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' CHANGELOG.md | head -1)

# Extrai a data do CHANGELOG.md
DATE=$(grep -o '\[[0-9]\+ de [A-Za-z]\+ de [0-9]\+\]' CHANGELOG.md | head -1 | sed 's/\[//;s/\]//')

# Se não encontrou a data, usa a data atual
if [ -z "$DATE" ]; then
    DATE=$(date +"%d de %B de %Y")
fi

# Inicializa o JSON
JSON='{
  "action": "add_version",
  "version": "'$VERSION'",
  "date": "'$DATE'",
  "categories": {'

# Função para extrair itens de uma categoria
extract_category_items() {
    local category_pattern="$1"
    local category_name="$2"
    
    # Encontra a seção da categoria
    local start_line=$(grep -n "$category_pattern" CHANGELOG.md | head -1 | cut -d: -f1)
    
    if [ -n "$start_line" ]; then
        # Extrai os itens até a próxima categoria ou fim do arquivo
        local items=$(sed -n "${start_line},/^### /p" CHANGELOG.md | grep "^- " | sed 's/^- \*\*[^:]*\*\*: //' | sed 's/^- //' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')
        
        if [ -n "$items" ]; then
            # Converte para array JSON
            local json_items=$(echo "$items" | sed 's/|/", "/g' | sed 's/^/["/;s/$/"]/')
            echo "    \"$category_name\": $json_items"
        fi
    fi
}

# Extrai as categorias encontradas
categories_found=false

# Procura por categorias específicas
if grep -q "✨" CHANGELOG.md; then
    if [ "$categories_found" = true ]; then
        JSON="$JSON,"
    fi
    JSON="$JSON$(extract_category_items "✨" "✨ Novas funcionalidades")"
    categories_found=true
fi

if grep -q "🐛" CHANGELOG.md; then
    if [ "$categories_found" = true ]; then
        JSON="$JSON,"
    fi
    JSON="$JSON$(extract_category_items "🐛" "🐛 Correções")"
    categories_found=true
fi

if grep -q "🎨" CHANGELOG.md; then
    if [ "$categories_found" = true ]; then
        JSON="$JSON,"
    fi
    JSON="$JSON$(extract_category_items "🎨" "🎨 Interface/Design")"
    categories_found=true
fi

if grep -q "🚀" CHANGELOG.md; then
    if [ "$categories_found" = true ]; then
        JSON="$JSON,"
    fi
    JSON="$JSON$(extract_category_items "🚀" "🚀 Melhorias gerais")"
    categories_found=true
fi

# Se não encontrou categorias específicas, agrupa tudo em "Novas funcionalidades e Correções"
if [ "$categories_found" = false ]; then
    # Extrai todos os itens que começam com "-"
    all_items=$(grep "^- " CHANGELOG.md | sed 's/^- \*\*[^:]*\*\*: //' | sed 's/^- //' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')
    if [ -n "$all_items" ]; then
        json_items=$(echo "$all_items" | sed 's/|/", "/g' | sed 's/^/["/;s/$/"]/')
        JSON="$JSON    \"✨ Novas funcionalidades e Correções\": $json_items"
    fi
fi

# Fecha o JSON
JSON="$JSON
  }
}"

echo "$JSON" 