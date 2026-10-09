# Guia de desenvolvimento ABAP do add-on (ZRX)

Regras para escrever os diagnósticos em ABAP. Vale para pessoas e para agentes de IA.

## 1. Sintaxe NetWeaver 7.00

Todo o código precisa compilar em NW 7.00 (decisão D17). O `pnpm abaplint` está configurado com `v700` e reprova sintaxe mais nova. Resumo do que **não** usar:

- `DATA(...)`, `FIELD-SYMBOL(...)`, `VALUE #( )`, `NEW #( )`, `CONV`, `COND`, `SWITCH`, `REDUCE`, `FOR`, `itab[ ... ]`
- string templates `|...|`, `boolc( )`, `xsdbool( )`, pragmas `##...` (use pseudo comentários `"#EC ...`)
- Open SQL novo (`@var`, lista de campos com vírgula, `CASE`/expressões no SELECT), CDS, AMDP
- `CONCATENATE ... RESPECTING BLANKS` (use `SEPARATED BY space`)
- método funcional como operando de `CONCATENATE` (guarde o resultado numa variável antes)

## 2. Estrutura de um diagnóstico

Cada diagnóstico tem três peças. Exemplo para SD:

| Objeto | Papel |
|---|---|
| `ZIF_RX_SD_READER` | Interface de leitura: **tipos** (estruturas com tipos ABAP embutidos, já harmonizados ECC/S4) e métodos que devolvem os dados. Nada de lógica de negócio |
| `ZCL_RX_SD_READER` | Implementação real: SELECTs nas tabelas SAP, diferença ECC × S/4 (`ZCL_RX_SYSTEM_INFO=>IS_S4( )`) e `AUTHORITY-CHECK` dos objetos standard |
| `ZCL_RX_DIAG_SD01` | Implementa `ZIF_RX_DIAGNOSTIC`. Recebe o leitor no construtor (`io_reader` opcional; sem ele cria o real) e a data de hoje (`iv_today` opcional; padrão `sy-datum`). Só lógica: decide os achados a partir dos dados |
| `zcl_rx_diag_sd01.clas.testclasses.abap` | Dublê local do leitor (`ltd_reader`) com dados em memória e testes que reproduzem os cenários do sap-mock |

Assim a lógica é testada sem SAP (`pnpm test:abap`), e o leitor real é validado depois no sistema (pendência V-SAP, ver `docs/pendencias-de-teste.md`).

### Leitor real: regras

- `SELECT` com lista de campos explícita (sem `SELECT *`), `UP TO n ROWS` nas listas e `FOR ALL ENTRIES` só com a tabela de entrada não vazia (verifique antes).
- Campos ou tabelas que existem só em um release (ex.: status SD em `VBUK` no ECC e em `VBAK` no S/4) devem ser lidos com **SQL dinâmico** (`SELECT (lt_campos) FROM (lv_tabela) ... WHERE (lv_where)`). SQL estático com um campo que não existe no release impede a compilação da classe naquele sistema.
- Autorização standard (ex.: `V_VBAK_VKO`) fica no leitor: um método `is_authorized( ... )` que o diagnóstico chama. Sem autorização, o diagnóstico levanta `ZCX_RX_ERROR` com HTTP 403 e código `NOT_AUTHORIZED`.
- Somente leitura: nenhum `INSERT`, `UPDATE`, `MODIFY`, `DELETE` ou `COMMIT WORK` em tabelas de negócio.

## 3. Paridade com o contrato e com o sap-mock

O resultado do ABAP precisa ser **igual ao do simulador** (`services/sap-mock/src/fixtures/*.ts`) nos pontos que a interface e a IA usam:

- códigos de achado (`SD01.CREDIT_BLOCK`…), severidade e ordem;
- ids dos fatos (`customer`, `netValue`, `stage:CREDIT`, `flag:LATE_FINISH`…);
- id das tabelas e as `keys` das colunas, na mesma ordem;
- `object.kind` / `object.id` (documento sem zeros à esquerda: `ZCL_RX_FORMAT=>ALPHA_OUT`);
- datas em `AAAA-MM-DD` (`ZCL_RX_FORMAT=>DATE_ISO`), quantidades e valores no padrão brasileiro (`QUANTITY`, `MONEY`).

Títulos e textos podem variar nas palavras, mas devem dizer a mesma coisa, em português.

Use `ZCL_RX_RESULT` para montar o resultado (`CREATE`, `ADD_FINDING`, `ADD_EVIDENCE`, `ADD_FACT`, `ADD_RELATED`, `ADD_COLUMN`, `SET_NOT_FOUND`, `SETTLE_STATUS`). O roteador preenche `diagnosticId`, `system`, `executedAt` e `durationMs`.

## 4. Arquivos (formato abapGit)

- Classe: `<nome>.clas.abap`, `<nome>.clas.xml` (com BOM UTF-8; copie o XML de uma classe existente e troque `CLSNAME` e `DESCRIPT`; `WITH_UNIT_TESTS` quando houver testes) e `<nome>.clas.testclasses.abap`.
- Interface: `<nome>.intf.abap` e `<nome>.intf.xml`.
- Nomes: classes/interfaces até 30 caracteres; tabelas até 16.
- Descrições (`DESCRIPT`) únicas, sem acentos.

## 5. Verificação obrigatória

```bash
pnpm abaplint    # 0 apontamentos
pnpm test:abap   # todos os testes ABAP Unit passando
```

O executor de testes roda o ABAP convertido para JavaScript (open-abap). Ele não substitui o teste no SAP real; o leitor real só é exercitado lá.
