# Ferramenta de licenças (fornecedor)

Gera o par de chaves, assina e inspeciona as licenças do Raio-X (D34, licença por usuário nomeado).
Só usa o Node 22 (sem dependências). **Uso interno do fornecedor**: a chave privada nunca vai para o repositório
nem para o servidor do cliente.

## Formato

```
RXL1.<base64url(payload JSON)>.<base64url(assinatura Ed25519 sobre os bytes do payload)>
```

Payload: `{ v: 1, licenseId, customer, tenantId?, edition, maxNamedUsers, issuedAt, expiresAt, deployment, features }`.
A API verifica a assinatura com a chave pública `VENDOR_PUBLIC_KEY` (`services/api/src/license/format.ts`).

## Comandos

```bash
# 1. Uma única vez: gera o par de chaves (guarde a privada em cofre)
node tools/license/license.mjs keygen --out ~/cofre/raiox

# 2. Assina uma licença de 10 usuários nomeados
node tools/license/license.mjs sign --key ~/cofre/raiox/raiox-license-private.pem \
  --customer "ACME S.A." --max-users 10 --expires 2027-12-31 \
  --edition standard --deployment selfhosted --feature chat --feature export

# 3. Confere o conteúdo (e a assinatura, se informar a chave pública)
node tools/license/license.mjs inspect licenca.lic --pub ~/cofre/raiox/raiox-license-public.pem
```

Opções do `sign`: `--tenant <id>` (vale só para esse cliente), `--deployment cloud|selfhosted|any` (padrão `any`),
`--edition standard|enterprise`, `--feature <nome>` (repetível), `--license-id`, `--issued`.
A data de `--expires` vale até o fim desse dia (UTC).

## Instalação no cliente

- Pela tela de administração (`PUT /api/v1/admin/license`): grava a licença no banco do cliente.
- Self-hosted, por arquivo: aponte `LICENSE_FILE` para o arquivo com o texto da licença.
  **Regra:** a licença gravada no banco (instalada pela administração) tem precedência; o arquivo só vale
  enquanto o banco não tem licença.

## Estados

| Estado | Quando | Efeito |
|---|---|---|
| `evaluation` | sem licença | até 5 usuários, com aviso |
| `valid` | dentro da validade | avisa quando faltam 30 dias ou menos, ou com 90% das vagas em uso |
| `grace` | até 15 dias após vencer | tudo funciona, com aviso ao usuário |
| `expired` | mais de 15 dias após vencer | só administradores entram (para instalar outra licença) |
| `invalid` | assinatura errada, modo de implantação ou cliente diferente | idem `expired` |

## Chave do fornecedor

A chave pública em `VENDOR_PUBLIC_KEY` é provisória. Antes de emitir licenças a clientes, o dono do produto gera o
par real com `keygen` e troca a constante. `LICENSE_PUBLIC_KEY` (PEM ou SPKI em base64) substitui a chave só para
testes e desenvolvimento; a API recusa essa variável com `NODE_ENV=production`.
