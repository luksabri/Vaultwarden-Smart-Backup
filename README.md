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

vaultwarden-smart-backup/
├── .gitignore
├── README.md
├── script/
│   └── backups.sh
└── n8n/
    └── workflow_vaultwarden_backup.json
