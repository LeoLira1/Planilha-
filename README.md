# CAMDA Divergências 📱

App Android (Flutter) para lançar **divergências de contagem** direto do celular,
sincronizado com o dashboard [CAMDA Estoque](https://github.com/LeoLira1/camda-estoque)
via banco **Turso** — é a versão mobile do expander
"⚠️ Registrar divergência de contagem" da seção Repor Loja.

## Como funciona

- O app escreve nas mesmas tabelas que o dashboard lê: `divergencias` e
  `historico_divergencias` (colunas `codigo, produto, categoria, delta, status,
  cooperado, criado_em`), com hora de Brasília no formato `YYYY-MM-DD HH:MM:SS`.
- Os produtos vêm de `estoque_mestre` (`codigo`, `produto`, `categoria`, `qtd_sistema`).
- `delta > 0` = **sobra**, `delta < 0` = **falta**. O valor do sistema **não é
  alterado** — apenas a divergência é registrada, igual ao dashboard.
- A aba **Ativas** lista as divergências abertas e permite resolvê-las com a
  mesma lógica do dashboard (remove o registro e, se for o último do produto,
  reseta o `estoque_mestre` para `ok`; o histórico é mantido).
- As divergências aparecem no dashboard no próximo sync/refresh dele (o cache
  do dashboard é de 60 s).

## Configuração (primeira vez)

1. Abra o app → ele leva direto para **Configurações**.
2. Informe a **URL do banco** (`TURSO_DATABASE_URL`, pode colar o `libsql://…`)
   e o **Auth token** (`TURSO_AUTH_TOKEN`) — os mesmos do dashboard.
3. Toque em **Testar conexão** — em caso de falha a mensagem mostra o erro
   real (DNS, HTTP 401, timeout, erro SQL…), nunca um erro genérico.
4. Na aba Registrar, digite a **senha de edição** (a mesma do expander do
   dashboard). Ela fica salva no aparelho depois do primeiro uso.

## Download do APK

Cada push gera build + APK automaticamente em
[**Releases**](../../releases) (workflow `.github/workflows/build.yml`).

- O APK é assinado com keystore fixo (`android/app/camda-release.jks`), então
  **atualizar é só instalar por cima** — sem "App não foi instalado".
- O `versionCode` é incrementado a cada build (`--build-number` = número do run).

> ⚠️ O keystore e suas senhas estão commitados no repositório por conveniência
> (app interno). Se o repositório for público, considere movê-los para GitHub
> Secrets.

## Estrutura

```
lib/
  main.dart              # app, tema escuro (paleta do dashboard) e abas
  registrar_tab.dart     # formulário: senha, produto, delta, cooperado
  divergencias_tab.dart  # lista de divergências ativas + resolver
  settings_screen.dart   # URL/token do Turso + teste de conexão
  turso_service.dart     # cliente HTTP do Turso (/v2/pipeline) + SQL
  models.dart            # Produto, Divergencia
android/                 # projeto Android completo (manifest já com INTERNET)
.github/workflows/build.yml  # build + release automáticos
```
