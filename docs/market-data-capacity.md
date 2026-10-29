# Market data: capacidade e operação

Atualização: 29/10/2026. Estado: base analítica com HTTP/snapshots; stream de preços e ordens paper ainda dependem de integração. Este documento não declara capacidade homologada.

## Limites implementados localmente

- Listagens: oito páginas por bloco (192 ações ou 400 linhas no screener), com recarga dos blocos anteriores. Offset de protocolo separado da deduplicação.
- DOM de ações/screener: janela medida, overscan de duas linhas de cards ou 12 linhas de tabela. Linha com foco permanece montada. Alternativa acessível por bloco.
- Histórico público em IndexedDB: schema 1, até 25 MiB de payload serializado, LRU, expiração em sete dias. O overhead físico do IndexedDB é adicional. Rede consultada em cada leitura porque o upstream ainda não oferece ETag/versão de ajuste confiável. Offline é identificado como desatualizado.
- Referências no ticker: polling de 30 segundos; uma requisição em andamento; cancelamento ao desmontar. Isso não representa ticks ou delay contratado.
- Cadastro público por ação: cache de servidor com stale/revalidate de 60 s e expiração máxima de 300 s; timeout de fetch de 8 s. A data de cache não é a data do fato.
- Carteira privada: fonte e instante do fato (`as_of`) obrigatórios para considerar uma cotação válida; idade máxima local do fato de cinco minutos. Sem calendário oficial integrado, esta é política conservadora de cache, não de validade de fechamento EOD. Falta de cobertura torna patrimônio/P&L total indisponível.

## Antes de ativar stream

Exigir fornecedor autorizado e contrato de moeda, sequência por instrumento/época, timestamps, delay e sessão. Preservar o SSE atual de sincronização. Medir conexões, assinaturas, eventos/s, bytes/s, filas, consumidores lentos, lacunas, replay e resync; definir orçamento, limites por cliente e modo degradado. Não registrar carteiras, tokens ou credenciais em logs públicos.

Dimensionamento ilustrativo do SDD: 10.000 eventos/s × 200 bytes = 2 MB/s antes de overhead; replicação integral para 100 clientes ≈ 200 MB/s. Não são medições do FIN e não servem como cota contratada.

## Runbook

1. Em falha de API/CDN, verificar erros e metadados; não preencher números ausentes com valores de exemplo.
2. Em P&L indisponível, conferir cobertura, origem, coleta e validade do preço. Nunca usar custo como cotação.
3. Em pregão suspeito, preservar o registro bruto; usar a migração aditiva de quarentena do lote SQL 16 após revisão e ensaio em banco isolado. Conferir fonte e calendário oficial antes de promover registros.
4. Caso um futuro stream apresente gaps, interromper aplicação incremental e obter snapshot com watermark. Reconectar passando por SYNCING; não afirmar LIVE antes de reconciliar.
5. Rollback de interface/cache não modifica ledger. Esta entrega não cria ledger ou roteador de ordens. Nenhuma migração foi aplicada automaticamente.

## Validação ainda exigida

Soak de 4h/8h com heap pós-GC, testes de ticks/gateway, reconexão de stream, concorrência durável de ordens e RUM de CWV continuam sem resultado. O teste local com 10.000 instrumentos verifica janela/retensão e acesso entre blocos, não estabilidade por horas nem capacidade de fanout. Consultar o relatório de execução no fin-docs para resultados e comandos.
