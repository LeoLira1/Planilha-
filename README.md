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

## "Failed host lookup" / erro de rede-DNS

Esse erro vem do Android, não do Turso: significa que o **aparelho não
conseguiu traduzir o nome do banco em um IP**. Ao tocar em **Testar conexão** o
app agora roda um diagnóstico e diz qual é o caso:

| Diagnóstico | Causa | O que fazer |
|---|---|---|
| Nome **não existe** no DNS público | URL errada/banco renomeado | copiar a URL exata em turso.tech → banco → *Connect* |
| Nome **existe**, mas o DNS do aparelho falha | resolvedor do celular/operadora, VPN, bloqueador de anúncios | desligar VPN/bloqueador, alternar Wi‑Fi ↔ dados móveis, ou Configurações → Conexões → Mais configurações de conexão → **DNS privado** → `one.one.one.one` |
| Nem TCP em `1.1.1.1:53` funciona | sem internet / modo avião / proxy | verificar a conexão do aparelho |
| Nome resolve, mas a conexão cai | firewall, proxy, rede corporativa | testar nos dados móveis |

Como isso é checado (`lib/net_diagnostico.dart`), sem depender do resolvedor do
Android: conexão TCP por IP literal + consulta DNS crua (UDP/53) direto ao
`1.1.1.1` e ao `8.8.8.8`. Toda falha de rede também é tentada **duas vezes**,
porque o primeiro lookup depois de trocar de Wi‑Fi/dados costuma falhar sozinho.

A URL é normalizada antes do uso (aceita `libsql://`, `wss://`, host puro;
remove espaços, caracteres invisíveis colados do WhatsApp/e-mail, caminho e
`?authToken=`), e a tela de Configurações mostra o endereço final que será
chamado.

## Estrutura

```
lib/
  main.dart              # app, tema escuro (paleta do dashboard) e abas
  registrar_tab.dart     # formulário: senha, produto, delta, cooperado
  divergencias_tab.dart  # lista de divergências ativas + resolver
  settings_screen.dart   # URL/token do Turso + teste de conexão
  turso_service.dart     # cliente HTTP do Turso (/v2/pipeline) + SQL
  net_diagnostico.dart   # por que o DNS falhou (TCP por IP + DNS público)
  models.dart            # Produto, Divergencia
android/                 # projeto Android completo (manifest já com INTERNET)
.github/workflows/build.yml  # build + release automáticos
```
