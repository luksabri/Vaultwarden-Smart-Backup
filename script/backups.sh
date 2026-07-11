#!/bin/bash

# ==============================================================================
# CONFIGURAÇÕES - AJUSTE DE ACORDO COM O SEU AMBIENTE
# ==============================================================================
CONTAINER_NAME="vaultwarden"
VOLUME_HOST_DIR="/home/ubuntu/docker/vaultwarden_data"
BACKUP_DIR="/home/ubuntu/backups"
WEBHOOK_URL="https://seu-n8n.seu-dominio.com/webhook/backup-vaultwarden"

# Configuração de data e nomenclatura (Mudado para .tar.gz)
DATA_ATUAL=$(date +"%d-%m_%H-%M")
NOME_ARQUIVO="vaultwarden_backup_${DATA_ATUAL}.tar.gz"
CAMINHO_FINAL="${BACKUP_DIR}/${NOME_ARQUIVO}"

# Garante a existência do diretório de backup
mkdir -p "$BACKUP_DIR"

# ==============================================================================
# 1. CONGELAMENTO E COMPACTAÇÃO SEGURA (DOCKER PAUSE + CONSOLIDAÇÃO WAL)
# ==============================================================================
echo "Congelando o container ${CONTAINER_NAME}..."
docker pause "$CONTAINER_NAME" > /dev/null

# Cria uma pasta temporária isolada para organizar o ecossistema do Vaultwarden
TMP_DIR=$(mktemp -d)

# 1. Copia o banco de dados principal e seus arquivos de log transacionais essenciais (WAL/SHM)
cp "${VOLUME_HOST_DIR}/db.sqlite3" "$TMP_DIR/" 2>/dev/null
[ -f "${VOLUME_HOST_DIR}/db.sqlite3-wal" ] && cp "${VOLUME_HOST_DIR}/db.sqlite3-wal" "$TMP_DIR/"
[ -f "${VOLUME_HOST_DIR}/db.sqlite3-shm" ] && cp "${VOLUME_HOST_DIR}/db.sqlite3-shm" "$TMP_DIR/"

# 2. Copia as chaves RSA existentes (como o seu rsa_key.pem)
[ -f "${VOLUME_HOST_DIR}/rsa_key.pem" ] && cp "${VOLUME_HOST_DIR}/rsa_key.pem" "$TMP_DIR/"
[ -f "${VOLUME_HOST_DIR}/rsa_key.der" ] && cp "${VOLUME_HOST_DIR}/rsa_key.der" "$TMP_DIR/"
[ -f "${VOLUME_HOST_DIR}/rsa_key.pub.der" ] && cp "${VOLUME_HOST_DIR}/rsa_key.pub.der" "$TMP_DIR/"

# 3. Copia diretórios adicionais de persistência caso venham a existir no futuro
[ -f "${VOLUME_HOST_DIR}/config.json" ] && cp "${VOLUME_HOST_DIR}/config.json" "$TMP_DIR/"
[ -d "${VOLUME_HOST_DIR}/attachments" ] && cp -r "${VOLUME_HOST_DIR}/attachments" "$TMP_DIR/"
[ -d "${VOLUME_HOST_DIR}/sends" ] && cp -r "${VOLUME_HOST_DIR}/sends" "$TMP_DIR/"

# Entra na pasta temporária e faz a compactação limpa
cd "$TMP_DIR" || exit
if tar -czf "$CAMINHO_FINAL" *; then
    STATUS_BACKUP="sucesso"
    echo "Backup completo (.tar.gz) gerado com sucesso em: ${CAMINHO_FINAL}"
else
    STATUS_BACKUP="erro"
    echo "Falha crítica ao gerar o arquivo de backup compactado."
fi

# Limpeza absoluta da pasta temporária do sistema
rm -rf "$TMP_DIR"

echo "Descongelando o container ${CONTAINER_NAME}..."
docker unpause "$CONTAINER_NAME" > /dev/null

# Inicialização da variável de controle de rotação
ARQUIVO_DELETADO="Nenhum (menos de 10 backups existentes)"

# ==============================================================================
# 2. ROTAÇÃO INTELIGENTE DE BACKUPS (RETENÇÃO: MÁXIMO 10 ARQUIVOS .TAR.GZ)
# ==============================================================================
if [ "$STATUS_BACKUP" = "sucesso" ]; then
    TOTAL_ARQUIVOS=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    if [ "$TOTAL_ARQUIVOS" -gt 10 ]; then
        # Identifica o arquivo compactado modificado há mais tempo na pasta
        ARQUIVO_ANTIGO=$(ls -t "$BACKUP_DIR"/*.tar.gz | tail -n 1)
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
  "mensagem": "Backup completo e compactado do Vaultwarden processado com pausa de seguranca.",
  "origem": "Servidor Oracle"
}
EOF
)

# Envio assíncrono via cURL (método POST)
curl -X POST "$WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD" \
     -s -o /dev/null

echo "Notificação enviada com sucesso para o orquestrador n8n."
