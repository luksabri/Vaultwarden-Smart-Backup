#!/bin/bash

# ==============================================================================
# CONFIGURAÇÕES - AJUSTE DE ACORDO COM O SEU AMBIENTE
# ==============================================================================
CONTAINER_NAME="vaultwarden"
VOLUME_HOST_DIR="/home/ubuntu/vaultwarden_data"
BACKUP_DIR="/home/ubuntu/backups"
WEBHOOK_URL="https://seu-n8n.seu-dominio.com/webhook/backup-vaultwarden"

# Configuração de data e nomenclatura
DATA_ATUAL=$(date +"%d-%m_%H-%M")
NOME_ARQUIVO="${DATA_ATUAL}.sqlite3"
CAMINHO_FINAL="${BACKUP_DIR}/${NOME_ARQUIVO}"

# Garante a existência do diretório de backup
mkdir -p "$BACKUP_DIR"

# ==============================================================================
# 1. CONGELAMENTO E CÓPIA SEGURA (DOCKER PAUSE)
# ==============================================================================
echo "Congelando o container ${CONTAINER_NAME}..."
docker pause "$CONTAINER_NAME" > /dev/null

# Execução da cópia física do banco de dados com as escritas travadas
if cp "${VOLUME_HOST_DIR}/db.sqlite3" "$CAMINHO_FINAL"; then
    STATUS_BACKUP="sucesso"
    echo "Backup copiado com sucesso em: ${CAMINHO_FINAL}"
else
    STATUS_BACKUP="erro"
    echo "Falha crítica ao copiar o arquivo de banco de dados."
fi

echo "Descongelando o container ${CONTAINER_NAME}..."
docker unpause "$CONTAINER_NAME" > /dev/null

# Inicialização da variável de controle de rotação
ARQUIVO_DELETADO="Nenhum (menos de 10 backups existentes)"

# ==============================================================================
# 2. ROTAÇÃO INTELIGENTE DE BACKUPS (RETENÇÃO: MÁXIMO 10 ARQUIVOS)
# ==============================================================================
if [ "$STATUS_BACKUP" = "sucesso" ]; then
    TOTAL_ARQUIVOS=$(ls -1 "$BACKUP_DIR"/*.sqlite3 2>/dev/null | wc -l)

    if [ "$TOTAL_ARQUIVOS" -gt 10 ]; then
        # Identifica o arquivo modificado há mais tempo na pasta
        ARQUIVO_ANTIGO=$(ls -t "$BACKUP_DIR"/*.sqlite3 | tail -n 1)
        ARQUIVO_DELETADO=$(basename "$ARQUIVO_ANTIGO")
        
        # Remoção física do arquivo excedente
        rm "$ARQUIVO_ANTIGO"
        echo "Rotação ativada. Arquivo antigo removido: ${ARQUIVO_DELETADO}"
    fi
fi

# ==============================================================================
# 3. DISPARO DO WEBHOOK PARA O N8N
# ==============================================================================
JSON_PAYLOAD=$(cat <<EOF
{
  "status": "$STATUS_BACKUP",
  "arquivo_criado": "$NOME_ARQUIVO",
  "arquivo_excluido": "$ARQUIVO_DELETADO",
  "mensagem": "Backup do Vaultwarden processado com pausa de seguranca."
}
EOF
)

# Envio assíncrono via cURL (método POST)
curl -X POST "$WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD" \
     -s -o /dev/null

echo "Notificação enviada com sucesso para o orquestrador n8n."
