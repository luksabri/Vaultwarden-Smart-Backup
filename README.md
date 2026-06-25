# Vaultwarden Smart Backup 🔐📦

Uma solução robusta, automatizada e de alta integridade para backup do servidor de senhas **Vaultwarden** rodando em ambientes Docker (testado e homologado em instâncias Ubuntu/Oracle Cloud Ampere).

## 🚀 Como Funciona a Lógica do Ecossistema

O projeto une a eficiência do Shell Script com o poder de orquestração do n8n e notificações em tempo real no Telegram:

1. **Agendamento (Cron):** O sistema aciona o script duas vezes ao dia (às 00:00 e às 12:00).
2. **Segurança Absoluta (Docker Pause):** O container do Vaultwarden é congelado por frações de segundo. Isso garante que nenhuma escrita ocorra no banco SQLite no momento da cópia, eliminando qualquer risco de corrupção de dados.
3. **Cópia e Nomeação:** O arquivo `db.sqlite3` é copiado para uma pasta de destino, recebendo o nome baseado no padrão `DIA-MES_HORA-MIN.sqlite3`.
4. **Descongelamento:** O container volta ao estado normal instantaneamente sem derrubar o serviço.
5. **Rotação Inteligente (Retenção de 10 dias/ciclos):** O script analisa a pasta de backups. Se houver mais de 10 arquivos, ele identifica e remove o mais antigo automaticamente, garantindo um histórico seguro de 5 dias de recuperação sem inflar o armazenamento do servidor.
6. **Notificação (n8n Webhook -> Telegram):** O script coleta as variáveis da operação (status, arquivo criado, arquivo deletado) e dispara um `POST JSON` para a API de Produção do n8n, que trata os dados e envia uma mensagem formatada com emojis ao administrador pelo Telegram.

---

## 📂 Estrutura do Repositório
```text
vaultwarden-smart-backup/
├── .gitignore
├── README.md
├── script/
│   └── backups.sh
└── n8n/
    └── workflow_vaultwarden_backup.json
```

## 🛠️ Tecnologias e Conceitos Utilizados
Shell Script (Bash): Automação, manipulação de arquivos e requisições HTTP (curl).

Docker Engine: Manipulação de estado de containers (pause / unpause).

Linux Cron: Agendamento de tarefas em nível de sistema operacional.

n8n: Orquestração de workflow baseado em eventos (Webhooks).

Telegram API: Notificação instantânea via Bot.

⚙️ Configuração e Instalação
1. Configuração do Script Bash
No seu servidor Ubuntu, mova o script backups.sh para a sua pasta de preferência (ex: /home/ubuntu/backups/) e ajuste as variáveis iniciais com os seus caminhos reais:
```bash

VOLUME_HOST_DIR="/caminho/do/seu/vaultwarden_data"
BACKUP_DIR="/home/ubuntu/backups"
WEBHOOK_URL="[https://seu-n8n.com.br/webhook/backup-vaultwarden](https://seu-n8n.com.br/webhook/backup-vaultwarden)"
```

Dê permissão de execução ao script:

```bash
chmod +x /home/ubuntu/backups/backups.sh
```
2. Agendamento no Cron
Abra o agendador do Linux:

```bash
crontab -e
```
## Adicione a seguinte linha ao final do arquivo para rodar de 12 em 12 horas (à meia-noite e ao meio-dia):
### Conferir o fuso horario do servidor.

```bash
0 0,12 * * * /bin/bash /home/ubuntu/backups/backups.sh > /dev/null 2>&1
```
3. Integração com o n8n e Telegram
Crie um Bot no Telegram usando o @BotFather e obtenha o seu Token de API.

Descubra o seu Chat ID pessoal utilizando o bot @userinfobot.

Importe o arquivo JSON contido na pasta /n8n do seu repositório diretamente para o painel do seu n8n.

Substitua as credenciais do Telegram e ative o fluxo utilizando a URL de Produção no script do servidor.

#📄 Licença
Este projeto está sob a licença MIT. Veja o arquivo LICENSE para mais detalhes.


---

### 2. O Script Limpo (`script/backups.sh`)
*Crie a pasta `script`, adicione o arquivo `backups.sh` e salve o código abaixo, que já está com dados genéricos de exemplo:*

```bash
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
