# Recuperação de ingestão sem infraestrutura paga

A engine e seu ledger ficam em fin-ingestion/PostgreSQL. O Worker Cloudflare é
apenas um disparador independente: a cada cinco minutos consulta Actions e
solicita `profile=recover` se não houver execução ativa ou concluída nos últimos
dez minutos. As referências são reconstruídas pelo ledger; o horário de chegada
do trigger não vira a data dos dados.

O código foi preparado para o plano gratuito de Workers. Implantar apenas numa
conta existente com plano gratuito; não ativar plano pago para contornar limites.

## Configuração

1. Autenticar a conta Cloudflare legítima. CAPTCHA, 2FA e confirmação de conta
   exigem o usuário. Não criar mecanismo para contornar essas verificações.
2. Criar token GitHub fine-grained restrito a `barrosrafa/fin-ingestion`, com
   permissão **Actions: read and write**, prazo de expiração e lembrete de rotação.
   Não copiar a credencial administrativa ampla do computador para o Worker.
3. Em `cloudflare/`, executar `npx wrangler login` e cadastrar os secrets
   `GITHUB_DISPATCH_TOKEN` e `HEALTH_TOKEN` com `wrangler secret put`. Nunca passar
   seus valores em argumento de comando, logs ou arquivo versionado.
4. Executar `npm ci`, `npm test`, `npm run deploy:dry-run` e `npm run deploy`. Conferir cron, conta e plano no
   painel; registrar nome/URL do Worker, sem credenciais, na evidência de release.
5. Invocar o endpoint com o health token sem registrar cabeçalho; conferir a
   execução `workflow_dispatch` e o recibo `data/runtime/summary.json` em Actions.
6. Testar a contingência em janela controlada: suspender só o cron nativo da
   engine, aguardar o dispatch externo e reabilitar o cron. Não desabilitar a engine.

## Limites

Os dois disparadores ainda dependem de GitHub Actions para executar. Queda de
Actions ou quota esgotada impede processamento; os jobs batch permanecem
recuperáveis no ledger. `ACTIVE` não comprova dados atualizados; a engine tem
timeout e o próximo ciclo recupera lease vencido. Falhas Cloudflare devem aparecer
na observabilidade do Worker. Alerta por um canal externo é configuração adicional,
não uma mensagem presumida como entregue.

Rollback: remover/desabilitar o cron do Worker e manter cron Actions + ledger.
Não apagar tarefas/cursor para desfazer deploy do disparador.


## Build vinculado ao Git

O código do Worker pertence a `barrosrafa/fin-infra`, branch `main`, diretório
`ingestion/cloudflare`. O destino do dispatch continua sendo o repositório
`barrosrafa/fin-ingestion` e o workflow `engine-schedule.yml`; esse é o alvo de
execução, não o repositório de build do Worker. Build command: `npm test`;
deploy command: `npm run deploy`. O Wrangler é fixado pelo package-lock e não
requer instalação global. Não vincular o build à raiz do projeto Python.

Antes do deploy, comparar variáveis remotas com `wrangler.jsonc`, preservar os
secrets existentes e guardar o ID da versão ativa. A presença dos nomes dos
secrets não prova que o token GitHub ainda seja válido: observar o resultado de
uma execução `scheduled` ou de uma chamada autenticada e o workflow correspondente.

Verificação em 01/11/2026: o vínculo incorreto com `fin-ingestion` foi substituído
por `fin-infra`, `main`, `ingestion/cloudflare`, usando o token de build existente.
Os comandos ficaram `npm test` e `npm run deploy`; builds de preview ficaram
desativados. Essa correção não altera o repositório destinatário dos dispatches.
