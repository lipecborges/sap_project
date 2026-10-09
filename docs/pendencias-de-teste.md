# Pendências de teste

Testes que o dono do projeto vai fazer depois. Eles precisam de ambiente real (chave da Anthropic, gestores do mercado, SAP, VM Linux), por isso não fazem parte do `pnpm test`.

Todos começam com status **⏳ Pendente**. Ao testar, troque o status para ✅ (passou) ou ❌ (falhou) e anote as observações, como descrito no fim deste arquivo.

---

## 1. Assistente de IA com o Claude (chave real)

**Preparação:** no arquivo `services/api/.env` (ignorado pelo git):

```bash
AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

Reinicie a API (`pnpm dev`). Os testes usam o `sap-mock` (`SAP_BASE_URL=http://localhost:8000`), onde os documentos dos exemplos existem.

| ID | Teste | Como fazer | Critério de pronto | Status |
|---|---|---|---|---|
| T-IA-01 | Conexão com o Claude | Abrir o Assistente com `AI_PROVIDER=anthropic` e fazer uma pergunta simples | Resposta chega sem erro de credencial (`Credencial da IA inválida`) | ⏳ Pendente |
| T-IA-02 | Diagnóstico certo, com evidência e transação | Fazer ~20 perguntas reais do dia a dia. Exemplos: (1) "Por que o pedido 4500001 não faturou?" (SD-01, bloqueio de crédito); (2) "Qual a situação da ordem 1000010?" (PP-03); (3) "Por que a fatura 5105600001 está bloqueada?" (MM-02, divergência de preço); (4) "Quais ordens estão atrasadas?" (PP-04); (5) "Me dá um panorama de hoje"; (6) "Por que meu pedido não faturou?" (sem número, ver T-IA-04) | Escolhe o diagnóstico esperado, cita a evidência e a transação de cada achado. Sugestão de meta: pelo menos 90% das perguntas certas (confirmar após a primeira rodada) | ⏳ Pendente |
| T-IA-03 | Não inventa dados | Perguntar por documento que não existe (ex.: "pedido 4599999") e por dado que o diagnóstico não devolve (ex.: "qual o CPF do cliente do pedido 4500001?") | Diz que não encontrou ou que o dado não está disponível. Nenhum número, status, nome ou valor inventado | ⏳ Pendente |
| T-IA-04 | Pergunta quando falta informação | Perguntas sem número de documento ou ambíguas (ex.: "por que meu pedido não faturou?") | Pede o número ou o tipo de documento antes de diagnosticar. Não escolhe um pedido por conta própria | ⏳ Pendente |
| T-IA-05 | Tempo de resposta e custo | Cronometrar 10 perguntas (do envio até a resposta completa). Anotar o custo do período no console da Anthropic e dividir pelo número de perguntas | Tempo mediano e custo médio por pergunta anotados. Servem de base para a franquia (projeto, seção 7.5) | ⏳ Pendente |
| T-IA-06 | Base para ajustar o prompt e montar os evals | Para cada resposta ruim, anotar: pergunta, resposta obtida, o que faltou e o resultado esperado | Lista de casos ruins com a causa provável (prompt, ferramenta ou modelo). Os casos viram cenários de eval (projeto, seção 7.6) | ⏳ Pendente |

---

## 2. Validação com o mercado

**Preparação:** demonstração com `pnpm dev` (sem chave, modo demonstração) e login **DEMO / demo**. Apresente a tela de Início e o Assistente.

| ID | Teste | Como fazer | Critério de pronto | Status |
|---|---|---|---|---|
| T-MKT-01 | Demonstração a gestores | Mostrar o modo demonstração a 3 a 5 gestores de consultorias AMS ou key users (cerca de 20 min cada) | 3 a 5 conversas feitas e registradas | ⏳ Pendente |
| T-MKT-02 | Resolve o dia a dia? | Perguntar: "Isto resolve os chamados do seu dia a dia? Quais?" | Resposta de cada pessoa registrada, com exemplos de chamados | ⏳ Pendente |
| T-MKT-03 | Diagnósticos que faltam | Perguntar: "Que diagnósticos você precisa e não existem aqui?" Comparar com o catálogo (`docs/catalogo-de-diagnosticos.md`, visão geral) | Lista de pedidos, com quantas pessoas citaram cada um | ⏳ Pendente |
| T-MKT-04 | Disposição a pagar e modelo de cobrança | Perguntar: "Pagaria? Quanto? Por usuário ou por sistema?" | Respostas registradas, com a faixa de preço citada. Alimentam a pendência Q8 (projeto, seção 16) e o modelo (seção 9) | ⏳ Pendente |
| T-MKT-05 | Cloud ou self-hosted | Perguntar: "Preferem usar na nuvem ou instalado no servidor de vocês? Por quê?" | Preferência e motivo registrados por entrevista (projeto, seção 4.4) | ⏳ Pendente |

---

## 3. Add-on ABAP num SAP real

**Pré-requisitos:**
- T-SAP-01 concluído, com `abap/INSTALACAO.md` seguido até o passo 4.
- Role `ZRX_USER` atribuída ao usuário de teste.
- Para PP-03 e PP-04: fonte do status "Aprovada" decidida (V07).

Para executar um diagnóstico, use `POST /sap/bc/zrx/api/v1/diagnostics/{id}` com curl ou Postman. Os parâmetros de cada diagnóstico aparecem em `GET /sap/bc/zrx/api/v1/diagnostics`.

| ID | Teste | Como fazer | Critério de pronto | Status |
|---|---|---|---|---|
| T-SAP-01 | Instalação via abapGit | Seguir `abap/INSTALACAO.md`, passos 1 a 4. Ativar todos os objetos | Objetos do pacote `ZRX` ativos, sem erro. `ZRX_LOG`, `ZRX_CONFIG` e `ZRX_PPSTAT_MAP` ativas. Serviço ICF ativo | ⏳ Pendente |
| T-SAP-02 | Health e me | `curl` em `/v1/health` e `/v1/me` com `?sap-client=` (passo 5 do guia) | Health devolve versão do add-on e dados do sistema. Me devolve o usuário e os diagnósticos permitidos | ⏳ Pendente |
| T-SAP-03 | Itens V01 a V14 do catálogo | Conferir cada item na transação indicada (`docs/catalogo-de-diagnosticos.md`, seção Checklist de validação). V01 a V12 em qualquer ECC ou S/4 com acesso legítimo. V13 em sistema 7.00. V14 na documentação do abapGit. Definir V07 | Cada item marcado como conferido ou corrigido no catálogo. V07 com a decisão registrada | ⏳ Pendente |
| T-SAP-04 | SD-01 em cenários reais | Executar SD-01 em pelo menos 5 pedidos: bloqueado por crédito, não bloqueado, já faturado e outros casos do catálogo | Resultado igual ao esperado: códigos de achado, severidade, ordem, fatos e colunas iguais ao `sap-mock` (`docs/abap-guia-desenvolvimento.md`, seção 3) | ⏳ Pendente |
| T-SAP-05 | SD-10 em cenários reais | Executar SD-10 em pelo menos 5 cenários de pedidos travados em etapas diferentes | Lista completa e na ordem certa, com a etapa de cada pedido igual ao esperado | ⏳ Pendente |
| T-SAP-06 | MM-02 em cenários reais | Executar MM-02 em pelo menos 5 faturas: bloqueio por preço, por quantidade, sem bloqueio e outros casos do catálogo | Resultado igual ao esperado, incluindo o motivo do bloqueio | ⏳ Pendente |
| T-SAP-07 | MM-10 em cenários reais | Executar MM-10 em pelo menos 5 cenários de faturas bloqueadas ou estacionadas | Lista completa, com status de cada fatura igual ao esperado | ⏳ Pendente |
| T-SAP-08 | PP-01 em cenários reais | Executar PP-01 em pelo menos 5 ordens: falta de componente, liberação automática, ordem liberada e outros casos | Causa (falta de material ou liberação) igual ao esperado, com as evidências corretas | ⏳ Pendente |
| T-SAP-09 | PP-03 em cenários reais | Executar PP-03 em pelo menos 5 ordens em situações diferentes (criada, liberada, apontada, entregue, atrasada) | Situação resumida igual ao esperado. Status "Aprovada" lido da fonte decidida em V07 | ⏳ Pendente |
| T-SAP-10 | PP-04 em cenários reais | Executar PP-04 com pelo menos 5 filtros (atrasadas, liberadas, falta de material etc.) em um centro | Lista igual ao esperado, com a tolerância de atraso de `ZRX_CONFIG` aplicada | ⏳ Pendente |
| T-SAP-11 | ECC e S/4 | Repetir T-SAP-04 a T-SAP-10 em um ECC e em um S/4 (ex.: sistema do CAL) | Mesmo resultado nos dois sistemas, sem erro de compilação e sem campo inexistente (ex.: status SD em `VBUK` no ECC e em `VBAK` no S/4) | ⏳ Pendente |
| T-SAP-12 | Usuário sem autorização | Com um usuário sem a role `ZRX_USER`, chamar `POST /v1/diagnostics/SD-01`. Depois, com a role, mas sem o diagnóstico liberado. Depois, sem a autorização standard do leitor (ex.: `V_VBAK_VKO` no SD) | HTTP 403 com código `NOT_AUTHORIZED` nos três casos. Nenhum dado devolvido | ⏳ Pendente |
| T-SAP-13 | Formatação no SAP real | Conferir a resposta de um pedido, uma ordem e uma fatura: datas, valores, quantidades e números de documento (`ZCL_RX_FORMAT`) | Datas em `AAAA-MM-DD`. Valores e quantidades no padrão brasileiro. Documentos sem zeros à esquerda. Igual ao `sap-mock` | ⏳ Pendente |
| T-SAP-14 | Log em `ZRX_LOG` | Após os testes anteriores, abrir a tabela `ZRX_LOG` na SE16 | Uma linha por execução bem-sucedida, com usuário, diagnóstico, resultado e duração. Pelo código atual, execuções negadas (403) não são gravadas: confirmar no sistema | ⏳ Pendente |
| T-SAP-15 | Suposições `(validar)` no código | Listar com `grep -rn "(validar)" abap/src` (21 pontos nos leitores SD, MM e PP) e conferir cada uma no sistema: valores de `CMGST`, `RBSTAT`, campos de `C_AFKO_AWK` e `M_RECH_WRK`, `RESB-XFEHL`, datas reais da ordem, link `BKPF-AWKEY`, `VBUK` × `VBAK` no S/4 etc. | Cada comentário `(validar)` removido (confirmado) ou o código corrigido, com o teste do cenário passando | ⏳ Pendente |
| T-SAP-16 | Desempenho das listas | Executar SD-10, MM-10 e PP-04 sem filtro num sistema com volume real e medir em `ZRX_LOG` (`DURATION_MS`). O MM-10 lê os itens fatura a fatura (até 2000) | Resposta em menos de 10 s. Se não, otimizar o leitor (ex.: JOIN ou faixas em lote) | ⏳ Pendente |

---

## 4. Infraestrutura

| ID | Teste | Como fazer | Critério de pronto | Status |
|---|---|---|---|---|
| T-INF-01 | Instalação self-hosted em VM Linux | Em uma VM com Docker, seguir `docs/instalacao-selfhosted.md` (`./install.sh --demo --build` com o simulador). Repetir com o SAP real, sem o perfil, apontando `SAP_BASE_URL`. Testar em Ubuntu, RHEL e SLES | Containers em execução. `http://<ip-da-vm>:8080` abre a web. Registrar a distro e a versão testadas | ⏳ Pendente |
| T-INF-02 | Smoke test do pacote | Rodar `RAIOX_URL=http://<ip-da-vm>:8080 node infra/selfhosted/smoke-test.mjs` | Todas as checagens com ✓: health, login, diagnóstico, painel, assistente e web | ⏳ Pendente |
| T-INF-03 | HTTPS com proxy reverso | Colocar um proxy reverso com TLS na frente da VM (ex.: Nginx ou Caddy, a confirmar). Definir `COOKIE_SECURE=true` no `.env` e reiniciar a API | Login funciona por HTTPS. O cookie de sessão tem os atributos Secure e HttpOnly (conferir no DevTools do navegador) | ⏳ Pendente |
| T-INF-04 | Acesso pelo celular na rede do cliente | Conectar o celular à rede interna do cliente. Abrir a URL HTTPS, entrar e rodar um diagnóstico | Login e diagnóstico funcionam. Tela se adapta ao celular, sem rolagem horizontal. Sessão expira após o tempo de inatividade (`SESSION_IDLE_MINUTES`) | ⏳ Pendente |
| T-INF-05 | Chave definitiva de licença | Rodar `node tools/license/license.mjs keygen` num computador seguro, guardar a chave privada fora do repositório (cofre) e trocar `VENDOR_PUBLIC_KEY` em `services/api/src/license/format.ts`. A chave atual é provisória e a privada dela foi descartada | Licença assinada com a chave nova é aceita pela tela Administração → Licença; a antiga é recusada | ⏳ Pendente |
| T-INF-06 | Conector na rede de um cliente | Criar o conector em Administração → Conectores, rodar o `docker run` mostrado numa máquina da rede do SAP e cadastrar o sistema com transporte "conector" (`docs/conector-instalacao.md`) | Conector aparece online; "Testar conexão" mostra a versão do add-on; login e diagnóstico funcionam por esse sistema. Só saída 443 liberada no firewall | ⏳ Pendente |
| T-INF-07 | Backup e restauração | Na VM, rodar `./backup.sh`, apagar um usuário de teste e rodar `./restore.sh <arquivo>` | Dados voltam; sessões ativas continuam válidas | ⏳ Pendente |
| T-INF-08 | Monitoramento | Definir `METRICS_TOKEN`, apontar um Prometheus (ou `curl -H "Authorization: Bearer …" /metrics`) | Métricas de requisições e de duração dos diagnósticos aparecem | ⏳ Pendente |

---

## Como registrar o resultado

1. Troque o status da linha: **✅** se passou, **❌** se falhou.
2. Para cada ❌, anote em uma lista logo abaixo da tabela, sob o título **Observações**: data, commit testado, ambiente (sistema, release e mandante, ou VM e distro), o que aconteceu e o que era esperado.
3. Se a falha exigir mudança no código ou no catálogo, abra um item separado. Não corrija o catálogo sem registrar a decisão.
4. Não coloque nomes de pessoas, empresas ou dados de clientes neste arquivo. Use códigos (ex.: G1, G2 para gestores).
