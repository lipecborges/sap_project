# Instalação do add-on no SAP

Guia para o consultor ABAP instalar o add-on Raio-X (pacote `ZRX`) num sistema SAP. Os objetos e a estrutura do código estão em `abap/README.md`.

> Sem o objeto de autorização `ZRX_DIAG` e a role `ZRX_USER` (passo 3), a execução de qualquer diagnóstico é negada com HTTP 403. Isso é proposital: nenhum dado sai do SAP sem autorização.

---

## 1. Pré-requisitos

| Item | Requisito |
|---|---|
| Release do SAP | NetWeaver 7.02 ou superior, para usar abapGit. No ECC 6.0, isso vale a partir do EHP5. Verificar em Sistema > Status (confirmar no sistema) |
| NetWeaver 7.00 ou 7.01 | Não usar abapGit. Entregar por ordem de transporte, caso a caso (projeto, seção 5.5). Os passos 3 a 7 valem do mesmo jeito |
| Usuário de desenvolvimento | Permissão para criar e ativar objetos no pacote `ZRX` (`S_DEVELOP`) e acesso às transações SICF, SU20, SU21, PFCG, SE11 e SE16 |
| Pacote `ZRX` | Criado na SE21, ou pelo próprio abapGit (confirmar no sistema) |
| abapGit | Instalado no sistema. Veja [abapgit.org](https://abapgit.org) |
| Usuário de teste | Um usuário **sem** a role `ZRX_USER`, para testar a negação (passo 3) |

---

## 2. Importar com abapGit

1. No abapGit, crie o repositório de uma das formas:
   - **Online:** use a URL do repositório Git do projeto (confirmar a URL com o dono do projeto).
   - **Offline:** use o arquivo `.zip` do repositório.
2. Confira a configuração. A pasta `/abap/src/` já está definida no `.abapgit.xml`. Aponte o pacote `ZRX`.
3. Faça o **Pull** e depois ative **todos** os objetos.

### Atenção às tabelas

| Tabela | Classe de entrega | O que é | O que fazer |
|---|---|---|---|
| `ZRX_LOG` | A (dados de aplicação) | Registro de cada execução | O abapGit traz só a estrutura, não os dados. Os registros crescem com o uso. Definir a política de retenção com o cliente |
| `ZRX_CONFIG` | C (customizing) | Configuração do add-on | O abapGit traz só a estrutura. Os valores são preenchidos em cada sistema (passo 6) |
| `ZRX_PPSTAT_MAP` | C (customizing) | Mapeamento de status da ordem de produção | Idem: preencher em cada sistema (passo 6) |

- Se a ativação falhar, ative as três tabelas primeiro, na SE11. Depois rode a ativação de novo.
- Para levar `ZRX_CONFIG` e `ZRX_PPSTAT_MAP` a outros sistemas, use uma ordem de transporte (confirmar no sistema).

---

## 3. Autorização

Esta etapa é obrigatória. Sem ela, nenhum diagnóstico roda.

### 3.1 Campo de autorização `ZRX_DIAGID` (SU20)

1. Na SU20, crie o campo `ZRX_DIAGID`.
2. Tipo CHAR, comprimento 10. O campo usa um elemento de dados. Se ele não existir, crie `ZRX_DIAGID` na SE11 como CHAR 10 e use-o na SU20 (confirmar no sistema).
3. O campo `ACTVT` já existe no SAP. Não é preciso criá-lo.

### 3.2 Objeto de autorização `ZRX_DIAG` (SU21)

1. Crie a classe de objeto `ZRX`, com o texto sugerido "Raio-X".
2. Crie o objeto `ZRX_DIAG` dentro dessa classe.
3. Inclua os campos `ZRX_DIAGID` e `ACTVT`.
4. A classe `ZCL_RX_AUTH` só aceita a atividade **16 = Executar**.

### 3.3 Role modelo `ZRX_USER` (PFCG)

1. Crie a role single `ZRX_USER` na PFCG.
2. Na aba de autorizações, inclua o objeto `ZRX_DIAG`.
3. Em `ZRX_DIAGID`, informe os diagnósticos liberados, um valor por vez (ex.: `SD-01`, `MM-02`). Um diagnóstico que não estiver na role não roda, mesmo com a role atribuída.
4. Em `ACTVT`, informe `16`.
5. Gere o perfil e atribua a role aos usuários que vão usar o Raio-X (confirmar no sistema).

---

## 4. Serviço ICF (SICF)

1. Na SICF, vá até `/default_host/sap/bc/zrx/api`.
2. Se os nós não existirem, crie `zrx` dentro de `sap/bc` e `api` dentro de `zrx`, como serviços hierárquicos (confirmar no sistema: os nomes dos menus variam conforme a versão).
3. No nó `api`, na aba **Handler list**, informe `ZCL_RX_HTTP_HANDLER`.
4. Na aba de logon, use o **logon padrão** (usuário e senha do SAP, Basic Auth).
5. Ative o serviço (Serviço > Ativar).

O add-on não guarda a senha. Cada chamada usa o usuário e a senha de quem está logado.

---

## 5. Teste rápido com curl

Troque `USUARIO`, `SENHA`, `<host>`, `<porta>` e a mandante (`100` no exemplo):

```bash
curl -u USUARIO:SENHA "http://<host>:<porta>/sap/bc/zrx/api/v1/health?sap-client=100"
curl -u USUARIO:SENHA "http://<host>:<porta>/sap/bc/zrx/api/v1/me?sap-client=100"
```

| Endpoint | Resposta esperada |
|---|---|
| `/v1/health` | JSON com a versão do add-on e os dados do sistema (SID, mandante e release) |
| `/v1/me` | JSON com o usuário e os diagnósticos que ele pode executar. Sem a role `ZRX_USER`, a lista sai vazia (confirmar no sistema) |

Se o acesso for por HTTPS, o certificado do servidor precisa ser confiável pelo computador que roda o curl. Não desative a verificação de certificado.

---

## 6. Configuração opcional

O add-on funciona com os valores padrão. Os passos abaixo são para ajustar o comportamento.

### 6.1 Tabela `ZRX_CONFIG`

Campos: `CONFIG_KEY` (até 40 caracteres) e `CONFIG_VALUE` (até 80 caracteres).

| CONFIG_KEY | CONFIG_VALUE | Efeito | Padrão |
|---|---|---|---|
| `DISABLED:<id>` (ex.: `DISABLED:SD-01`) | `X` | Desliga o diagnóstico | Ligado |
| `PP_LATE_TOLERANCE_DAYS` | Número de dias (ex.: `2`) | Tolerância, em dias corridos, antes de marcar a ordem como atrasada | `0` |
| `MAX_ROWS` | Número (ex.: `200`) | Limite de linhas nas listas | `500` |
| `PP_FIELD_TABLES` | Tabelas separadas por vírgula (ex.: `AUFK,AFKO,AFPO`) | Tabelas permitidas na fonte `FIELD` da `ZRX_PPSTAT_MAP` | `AUFK,AFKO,AFPO` |

Edite pela SE16 ou pela SM30, se houver view de manutenção (confirmar no sistema).

### 6.2 Tabela `ZRX_PPSTAT_MAP`

Campos: `SOURCE_TYPE` (`SYSTEM_STATUS`, `USER_STATUS` ou `FIELD`), `SOURCE_VALUE` (valor da fonte) e `SITUATION` (situação usada pelo Raio-X). Na fonte `FIELD`, o valor tem o formato `TABELA-CAMPO=VALOR` (ex.: `AUFK-USER0=A`).

Exemplo: o status de usuário `E0002`, do perfil `ZPP00001`, vira a situação `APPROVED`.

| SOURCE_TYPE | SOURCE_VALUE | SITUATION |
|---|---|---|
| `USER_STATUS` | `ZPP00001/E0002` | `APPROVED` |

Status sem mapeamento aparecem com o texto original. Situações aceitas em `SITUATION`: `APPROVED`, `CREATED`, `RELEASED`, `IN_PRODUCTION`, `CONFIRMED`, `PARTIALLY_DELIVERED`, `DELIVERED`, `TECHNICALLY_COMPLETED`, `CLOSED`, `DELETED` (classe `ZCL_RX_PP_STATUS_MAP`). Com `BLOCKS_RELEASE`, o status de usuário passa a ser tratado como bloqueio de liberação no PP-01.

---

## 7. Apontar a API do Raio-X para o SAP

No arquivo `services/api/.env` (ou `infra/selfhosted/.env`, no self-hosted):

```bash
DEPLOYMENT_MODE=selfhosted
SAP_BASE_URL=http://<host>:<porta>
SAP_CLIENT=100
```

- `SAP_BASE_URL` é só o endereço do servidor. A API acrescenta o caminho `/sap/bc/zrx/api/v1`.
- Reinicie a API e entre na web com um usuário SAP.

---

## 8. Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| **401** `UNAUTHENTICATED` | Usuário ou senha errados, usuário bloqueado no SAP, ou sessão do Raio-X expirada | Testar o logon do usuário no SAP. Conferir se o usuário não está bloqueado (SU01). Se a sessão expirou, entrar de novo |
| **403** `NOT_AUTHORIZED` | Falta o objeto `ZRX_DIAG`, o campo `ZRX_DIAGID` ou a atividade 16 na role. Ou o diagnóstico não está na role | Conferir a role do usuário na PFCG. Logo após o erro, abrir a SU53 e ver o último objeto negado (confirmar no sistema) |
| **404** `ROUTE_NOT_FOUND` | Caminho errado, serviço ICF inativo ou sem handler | Conferir a URL (`/sap/bc/zrx/api/v1/...`) e o serviço na SICF (passo 4). Confirmar que o handler é `ZCL_RX_HTTP_HANDLER` |
| Sistema **não-Unicode** | ECC antigo: acentos saem errados ou se perdem | Testar com dados acentuados (ex.: nome de cliente). Registrar o caso e avisar o dono do projeto (projeto, seção 5.5) |
| **TLS** antigo: falha na conexão HTTPS | Kernel sem suporte a TLS 1.2 | Falar com a Basis. Dentro da rede do cliente, usar HTTP se a política permitir (projeto, seção 5.5). Não desligar a verificação de certificado no Raio-X |
