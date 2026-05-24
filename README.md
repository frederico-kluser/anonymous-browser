<p align="center">
  <img src="logo.jpg" alt="anonymous-browser" width="220"/>
</p>

<h1 align="center">anonymous-browser</h1>

> **Sua sessão. Seu IP. Seu fingerprint. Sua escolha.**
>
> Um navegador descartável, isolado, com IP rotacionado pelo Tor e fingerprint coerente trocado em nível C++. Linux (Debian/Arch/Fedora + Flatpak fallback) e macOS. Bash. Sem telemetria. Sem conta. Sem rastro.

```bash
npm i -g anonymous-browser   # uma vez
anonymous-browser            # toda vez que quiser uma identidade nova
```

---

## Por que isto existe

A web de 2026 não te trata como visitante. Te trata como **target**. Cada `fetch()` que seu browser faz num site arbitrário sai com:

- IP público (resolvível pra cidade, ISP, AS, e muitas vezes pra você como pessoa)
- Canvas hash, WebGL renderer, audio fingerprint, lista de fontes, screen + colorDepth, `Intl.timeZone`, `navigator.platform`, Client Hints, `userAgentData.brands`
- Cookies, localStorage, IndexedDB, ServiceWorker caches, ETags persistentes
- TLS JA3/JA4, HTTP/2 SETTINGS frame fingerprint, ordem de headers

Combinando esses sinais, um único site identifica você unicamente em **>99% das visitas** ([Panopticlick](https://amiunique.org), [FingerprintJS](https://fingerprint.com)). Cookie-clearing, modo anônimo e VPN básica resolvem **nenhum** dos vetores acima.

**anonymous-browser** é o oposto político disso: uma stack curta de scripts shell que monta, antes de cada sessão, uma máquina virtual de identidade — IP, fingerprint, locale, geo, timezone — coerente o suficiente pra passar em CreepJS com Trust >70% e descartável o suficiente pra desaparecer no `Ctrl+C`.

Isso não é furtar. Isso é **se recusar a pagar com seus dados** o pedágio que sites cobram pra te deixar entrar. É o mesmo princípio das listas de domínio do uBlock Origin, do Tor Project, do EFF Privacy Badger, do Mullvad VPN: na ausência de uma lei honesta de privacidade, você se defende sozinho.

> "Privacy is necessary for an open society in the electronic age. Privacy is not secrecy."
> — Eric Hughes, *A Cypherpunk's Manifesto* (1993)

---

## TL;DR

```bash
# via npm (recomendado): instala um comando 'anonymous-browser' no seu PATH
npm i -g anonymous-browser
anonymous-browser
```

Na primeira execução o comando dispara `install.sh` automaticamente (instala Tor, libs nativas do Camoufox e o venv Python — pede sudo). Depois disso, cada execução pergunta se você quer um e-mail temporário descartável e abre o browser.

Quer rodar do source sem npm?

```bash
git clone https://github.com/frederico-kluser/anonymous-browser
cd ghost-browser
./install.sh
./anonymous.sh
```

`anonymous-browser` (ou `./anonymous.sh`) te pergunta a URL, sorteia um OS pra spoofar (windows/macos/linux), força um novo circuito Tor, abre um Firefox-patched (Camoufox) com fingerprint coerente, **nega GPS silenciosamente** e apaga tudo (perfil temporário, browser, processo) no momento que você fecha o navegador, dá Ctrl+C ou fecha o terminal.

---

## O que rola debaixo do capô

| Vetor | Defesa |
|---|---|
| IP / ASN / geo | Tor SOCKS5 em `127.0.0.1:9050`, novo circuito por sessão via `new-tor-circuit.sh` |
| Cookies, storage, cache | Perfil em `mktemp -d`, apagado por `trap INT TERM HUP EXIT` |
| Canvas / WebGL / Audio / Fonts | Camoufox patcha em C++ (Firefox fork da [BrowserForge](https://github.com/daijro/camoufox)) |
| `navigator.platform`, Client Hints, `userAgentData` | Camoufox `os="windows"\|"macos"\|"linux"` — coerentes entre si |
| `Intl.timeZone`, `navigator.language` | Camoufox `geoip=True` → bate com cidade do exit Tor (dataset MaxMind) |
| WebRTC IP leak | Camoufox `block_webrtc=True` (default) |
| HTML5 Geolocation API | `firefox_user_prefs={"permissions.default.geo": 2}` → site recebe `PERMISSION_DENIED` sem prompt |
| Botão "X" do navegador | `BrowserContext.wait_for_event("close")` → encerra script + apaga perfil |
| Proxy / VPN customizado | env var `PROXY=socks5://...` sobrescreve Tor default; `PROXY=none` desliga proxy |
| Identidade persistente | env var `KEEP=nome` salva perfil em `~/.anonymous-browser/profiles/<nome>/` com OS fixado |

E o que **não** dá pra resolver com esta stack — sendo honesto:

- **Anti-bot enterprise** (Cloudflare Bot Management, DataDome, PerimeterX, Kasada). Esses caras analisam TLS JA3, HTTP/2 frame ordering, comportamento de mouse com ML. Camoufox melhora mas não esconde. Se você precisa passar por isso, vai pagar GoLogin, Multilogin, AdsPower — não é missão deste repo.
- **Mobile fingerprint coerente.** Camoufox só suporta desktop (`windows`/`macos`/`linux`). Removemos os perfis iPhone/iPad/Android do projeto para não dar falsa sensação de proteção — qualquer anti-bot detectava como inconsistente.
- **Identidade externa.** Se o site quer SMS/e-mail único, você precisa de [addy.io](https://addy.io), [SimpleLogin](https://simplelogin.io), número descartável. Fora do escopo.

---

## Anatomia técnica

> Esta seção lista, **sem omissões**, cada técnica usada pelo `anonymous-browser` e como ela é implementada. A intenção é que você possa auditar tudo lendo o código — cada subseção referencia o arquivo e o bloco relevantes. Se algo está aqui, está no código. Se está no código mas não está aqui, é bug de documentação — abra issue.

### 1. Camada de rede

#### 1.1 Tor SOCKS5 como default

Sem `PROXY` setado (ou com `PROXY=tor`), o tráfego do navegador sai pelo Tor local em `127.0.0.1:9050`. Tor já vem instalado pelo `install.sh` e habilitado como serviço (`systemctl enable --now tor` no Linux, `brew services start tor` no macOS — ambos persistem entre boots).

Arquivo: `anonymous.sh`, bloco `# -------- resolve PROXY --------`. O default está no `case` `""|tor) PROXY_URL="socks5://127.0.0.1:9050"`.

#### 1.2 Proxy custom via `$PROXY`

Quatro modos aceitos: `tor` (default), `none` (sem proxy — IP real), `socks5://host:port`, `http(s)://host:port`. Qualquer outro valor faz o script abortar antes de tocar no navegador. SOCKS4 **não** é suportado — limitação do Playwright (engine do Camoufox), explicitada no comentário do código.

Arquivo: `anonymous.sh`, mesmo bloco. Validação por `case` exclusivo.

#### 1.3 DNS resolvido pelo proxy (não pelo resolver do sistema)

Quando o proxy é SOCKS5, todas as chamadas de `curl` que o `anonymous-browser` faz usam `--socks5-hostname` em vez de `--socks5`. A diferença é crítica: `--socks5-hostname` envia o **nome** do host para o proxy resolver; `--socks5` resolve localmente e só manda o IP. Sem `--hostname`, seu resolver DNS do sistema (ISP, Google 8.8.8.8) veria todas as queries — leak de DNS clássico.

Arquivo: `lib/platform.sh`, função `anon_curl_proxy_args()`. O comportamento é simétrico ao que `install.sh` usa pra testar Tor (`--socks5-hostname 127.0.0.1:9050`).

#### 1.4 Rotação de circuito Tor (NEWNYM + fallback de reload)

Antes de abrir o navegador (quando proxy é Tor), o `anonymous-browser` força um circuito novo — IP de saída diferente do que você acabou de usar. Dois caminhos:

- **Caminho rápido**: se você habilitou `ControlPort 9051` no `torrc`, mandamos `AUTHENTICATE "" / SIGNAL NEWNYM / QUIT` via `nc 127.0.0.1 9051`. Tor renova circuitos sem reiniciar. Latência: ~1s.
- **Fallback**: se ControlPort estiver fechada, fazemos reload do serviço (`sudo systemctl reload tor` ou `brew services restart tor`). Funciona, mas é mais lento (~5–15s) e fecha qualquer conexão Tor ativa.

Arquivo: `new-tor-circuit.sh`. A escolha do caminho é decidida por `anon_port_open 127.0.0.1 9051`.

#### 1.5 Probe de IP de saída via endpoint Tor-friendly

Cloudflare hoje bloqueia o conjunto clássico de endpoints de "qual é meu IP" (`api.ipify.org`, `ipinfo.io`, `checkip.amazonaws.com`, `icanhazip.com`) quando a origem é exit Tor — devolvem HTTP 403 ou corpo vazio. Se o Camoufox tentasse o auto-probe interno dele, levantaria `InvalidIP` e o navegador **nunca abriria**.

Resolução: o `anonymous-browser` resolve o IP de saída **no próprio shell** consultando `https://check.torproject.org/api/ip` (purpose-built pra detectar Tor, nunca bloqueia), parseia `.IP` com `jq`, e passa o IP como string para `geoip=` do Camoufox. Tem fallback para `icanhazip.com`, `ifconfig.co/ip`, `ipecho.net/plain` quando o proxy não é Tor.

Se todos falham (rede caída, todo mundo bloqueado): cai para `geoip=False` com aviso, mas o **navegador ainda abre** — preferimos identidade levemente inconsistente a sessão impossível.

Arquivo: `anonymous.sh`, bloco `# -------- resolve IP de saída para geoip --------`.

---

### 2. Camada de fingerprint (Camoufox + BrowserForge)

#### 2.1 Por que Camoufox e não plugin / extensão

A maioria dos anti-detect "soluções" baratas spoofa `navigator.platform` via hook JavaScript injetado no documento. Detectar isso é trivial: o site checa `navigator.platform.toString.toString()` ou compara `Object.getOwnPropertyDescriptor(navigator, 'platform').get` com o esperado, ou simplesmente carrega um `iframe` cuja janela ainda tem o platform real.

[Camoufox](https://github.com/daijro/camoufox) é um **fork do Firefox** que patcha os valores **em C++**, antes de o JS ser executado. Não há `Function.prototype.toString` que delate o hook, porque não existe hook — o valor é genuíno no nível do engine. É o mesmo princípio que o Tor Browser usa, exceto que Camoufox spoofa **uma identidade arbitrária** em vez de uma uniforme.

#### 2.2 OS spoof coerente

`anonymous-browser` escolhe (ou recebe via `ANON_OS`) um entre `windows`, `macos`, `linux`. Esse único valor cascateia em **dezenas** de subvetores que Camoufox alinha sozinho:

- `navigator.platform` (`Win32` / `MacIntel` / `Linux x86_64`)
- `navigator.userAgent` (versão de Firefox compatível com o OS)
- `navigator.userAgentData.brands` / `.platform` (Client Hints)
- Headers HTTP `Sec-CH-UA-Platform`, `Sec-CH-UA-Platform-Version`
- Lista de fontes disponíveis (`Segoe UI` aparece no Windows, não no Linux)
- Vendor / Renderer de WebGL coerentes (`ANGLE (NVIDIA…)` no Windows, `Apple Inc.` no macOS)

A coerência interna é o que detectores procuram. Spoofar UA pra Windows e deixar `navigator.platform="Linux x86_64"` é detectado em milissegundos por qualquer fingerprinter sério. Camoufox + BrowserForge sincronizam todos os campos antes do primeiro byte ir pro site.

Arquivo: `anonymous.sh`, bloco `# -------- resolve ANON_OS --------` + chamada `Camoufox(os=OS_ARG, ...)`.

#### 2.3 Screen, fontes, Canvas, WebGL, Audio context

| Vetor | Como spoofamos |
|---|---|
| Screen | `Screen(max_width, max_height)` da `browserforge.fingerprints` — limites por OS (`1920×1080` win/linux, `2560×1600` macos). Camoufox sorteia dentro do limite. |
| Fontes | Dataset bundled da BrowserForge — Camoufox restringe a `document.fonts` ao set típico do OS sorteado. |
| Canvas | Patch C++: `HTMLCanvasElement.prototype.toDataURL` retorna pixels com ruído determinístico **por sessão**, mas constante entre frames da mesma sessão (anti-detecção de "noise random per call"). |
| WebGL | Vendor / Renderer / `UNMASKED_VENDOR_WEBGL` / `UNMASKED_RENDERER_WEBGL` reescritos no Firefox patched, casando com o OS. |
| Audio | `AudioContext.createOscillator` retorna buffer levemente alterado — quebra `audioContext.fingerprint` da FingerprintJS. |

Tudo isso é feito pelo Camoufox/BrowserForge — não há código nosso aqui além de **escolher o OS** e passar a `Screen` correta. A "magia" toda mora no fork do Firefox.

Arquivo: `anonymous.sh`, dict `screens = {...}` + bloco `with Camoufox(...)`.

#### 2.4 Client Hints (`Sec-CH-UA-*`)

Chromium e Firefox modernos mandam um set de headers que o site explicitamente requisita (`Accept-CH`). Esses headers **não** estão expostos a `navigator.userAgent` — um spoof clássico de UA não os afeta. Camoufox os patcha em nível de rede no Firefox patched, casando com o OS spoofado.

Verificável: abra `https://browserleaks.com/javascript` dentro do `anonymous.sh` e compare a seção "User-Agent Client Hints" com o OS sorteado.

#### 2.5 Humanização de interação

`Camoufox(humanize=True)` injeta micro-delays entre eventos (mouse-move, keypress) seguindo distribuições típicas de humano. **Não** é bot-puro com `page.click()` instantâneo. Útil contra trackers comportamentais simples (`requestAnimationFrame`-based behavioral detection); inútil contra ML-based behavioral (Datadome, Akamai BMP) — esses casos exigem stack diferente.

Arquivo: `anonymous.sh`, kwarg `humanize=True` na chamada `with Camoufox(...)`.

#### 2.6 WebRTC bloqueado (anti-leak de IP real)

Mesmo com proxy SOCKS5, WebRTC clássico (`RTCPeerConnection`) faz STUN/TURN diretos que ignoram proxy HTTP/SOCKS — vazam IP local e público em segundos. Camoufox traz `block_webrtc=True` como **default** — o stack inteiro de WebRTC fica desligado no Firefox patched. Não é configurável a partir do nosso `anonymous.sh` (intencional: ligar WebRTC anula meio Tor).

Verificável: `https://browserleaks.com/webrtc` deve mostrar "No leaks".

#### 2.7 HTML5 Geolocation API negada silenciosamente

`firefox_user_prefs={"permissions.default.geo": 2}` — `2` significa **deny implícito** sem mostrar prompt ao usuário. Sites recebem `PERMISSION_DENIED` instantaneamente quando chamam `navigator.geolocation.getCurrentPosition()`. Diferente do default Firefox (`0` = prompt), que daria pop-up — sinal forte de fingerprint atípico.

Arquivo: `anonymous.sh`, kwarg `firefox_user_prefs={"permissions.default.geo": 2}` no `Camoufox(...)`.

---

### 3. Camada geográfica (geoip)

#### 3.1 IP → locale + timezone + idioma

Camoufox consulta o dataset MaxMind GeoLite2 (baixado pelo `install.sh` via `python -m camoufox fetch`, ~65 MB) para mapear o IP de saída em:

- `Intl.DateTimeFormat().resolvedOptions().timeZone` — timezone coerente com a cidade do exit
- `navigator.language` / `navigator.languages` — idioma típico da região (pt-BR no Brasil, fr-FR na França, etc.)
- Locale do Firefox (formato de datas, moeda)

Sem isso, você pareceria "ucraniano com timezone de NY" para qualquer site que cruza esses sinais.

#### 3.2 Workaround Cloudflare (resolução fora do Camoufox)

Como descrito em §1.5: Camoufox `geoip=True` tentaria descobrir o IP via `api.ipify.org`/`ipinfo.io` — tudo Cloudflare-blocked pra exits Tor. Resolvemos o IP no shell e passamos como string explícita: `geoip="185.220.101.42"`.

#### 3.3 Privacidade com `PROXY=none`

Quando você desliga o proxy, **automaticamente** desabilitamos `geoip` (`geoip_kw = False`). Razão: se o Camoufox fizer auto-probe de IP, ele vai bater em `api.ipify.org` **com seu IP real** — o IP que você acabou de pedir pra esconder. Trade-off: sem `geoip`, locale/timezone podem não bater com sua região real (alguns sites notam), mas seu IP fica em casa.

Arquivo: `anonymous.sh`, bloco final no heredoc Python — `if proxy_arg is None: geoip_kw = False`.

---

### 4. Camada de sessão (perfis)

#### 4.1 Perfil descartável

Sem `KEEP`, o `user_data_dir` do Firefox é criado via `mktemp -d "$(anon_tmp_prefix)/anon-XXXXXX"`. `anon_tmp_prefix()` retorna `$TMPDIR` no macOS (`/var/folders/.../T/`) ou `/tmp` no Linux. Tudo (cookies, localStorage, IndexedDB, ServiceWorker caches, ETags) vive só dentro desse dir e é apagado pelo `trap` no `EXIT`.

Por que perfil temporário e não anônimo do Firefox? Modo anônimo do Firefox **persiste** alguns artefatos entre janelas privadas no mesmo processo, e principalmente **não isola fingerprint** — o objetivo aqui é zero state, não privacidade-de-cookies.

Arquivo: `anonymous.sh`, bloco `# -------- perfil descartável OU persistente --------`.

#### 4.2 Perfil persistente (`KEEP=nome`)

Setando `KEEP=trabalho`, o perfil vive em `~/.anonymous-browser/profiles/trabalho/`. Cookies, histórico, logins, extensões — tudo persiste entre execuções. Útil pra ter identidades alternativas estáveis (uma "pessoa" pra trabalho, outra pra pessoal, sem cross-contamination).

Validação: `KEEP` precisa casar `^[A-Za-z0-9_-]+$`. Sem `.`, sem `/`, sem espaço — previne path traversal e nomes problemáticos no `mkdir -p`.

Arquivo: `anonymous.sh`, bloco `# -------- resolve KEEP --------`.

#### 4.3 OS pinning per perfil persistente

Cada perfil persistente memoriza o OS sorteado na primeira vez, num arquivo `.anon-os` dentro do próprio perfil. Sessões subsequentes leem o OS do arquivo (sem sorteio novo), mantendo a identidade coerente entre as visitas — `navigator.platform` não pula de `Win32` pra `MacIntel` entre execuções, o que delataria spoofing.

Override possível: `ANON_OS=macos KEEP=trabalho ...` reescreve o `.anon-os` na hora.

Arquivo: `anonymous.sh`, bloco `# -------- resolve ANON_OS --------` (lógica de leitura/escrita do `OS_FILE`).

#### 4.4 Bloqueio até o usuário fechar o navegador

O Python espera por `browser.wait_for_event("close", timeout=0)` — timeout zero = infinito. O evento `close` é disparado quando o **processo Firefox** termina (todas as janelas fechadas, ou kill no processo). Enquanto o navegador está aberto, o shell fica passivamente bloqueado — zero CPU.

Arquivo: `anonymous.sh`, dentro do `with Camoufox(...)`. Note que `KeyboardInterrupt` e `SystemExit` são capturados pra cleanup limpo em Ctrl+C / SIGTERM.

#### 4.5 `page.goto` com timeout não-fatal

Tor com exit ruim pode demorar >30s pra responder. Default do Playwright derruba a sessão com `TimeoutError`. Aumentamos pra 60s **e** capturamos a exceção: se `goto` falhar, imprimimos aviso e **a janela continua aberta** — você decide se recarrega, troca circuito (`./new-tor-circuit.sh`), ou desiste com Ctrl+C.

Arquivo: `anonymous.sh`, dentro do `with Camoufox(...)` — bloco `try: page.goto(URL, timeout=60_000)`.

---

### 5. Camada de processo (sinais e cleanup)

#### 5.1 Quatro sinais cobertos: INT, TERM, HUP, EXIT

```bash
trap cleanup INT TERM HUP EXIT
```

- `INT` (SIGINT) — Ctrl+C no terminal
- `TERM` (SIGTERM) — `kill <pid>` ou `systemctl stop`
- `HUP` (SIGHUP) — terminal fechado (SSH disconnect, fechar janela do gnome-terminal)
- `EXIT` — qualquer saída do script, incluindo `exit 0` normal e erros via `set -e`

O `cleanup()` é idempotente: mata o watcher de e-mail (se MAIL=1), espera ele encerrar com `wait`, e apaga o `$TMP` se for perfil descartável. Garante que **nenhum** caminho de saída deixa lixo.

Arquivo: `anonymous.sh`, função `cleanup()` no topo do script.

#### 5.2 Sinais Python espelham os do bash

Dentro do heredoc Python:

```python
for s in (signal.SIGHUP, signal.SIGTERM):
    signal.signal(s, lambda *_: sys.exit(0))
```

Razão: `SIGINT` o Python já converte em `KeyboardInterrupt` sozinho. `SIGHUP` e `SIGTERM` por default **matam o processo** sem rodar `finally` — perderíamos a chance de fechar o Camoufox educadamente. Convertendo em `sys.exit(0)`, o `with` do context manager dispara `__exit__` e fecha o browser apropriadamente.

#### 5.3 Mail watcher cleanup (kill + wait)

Quando `MAIL=1`, `anonymous-mail.sh` roda em background com seu próprio PID. O `cleanup()` do `anonymous.sh` faz `kill "$MAIL_PID"` seguido de `wait "$MAIL_PID"`. O `wait` é importante: dá tempo do trap do `anonymous-mail.sh` rodar (que apaga a conta no mail.tm), antes do shell pai sair. Sem `wait`, a conta efêmera vaza no mail.tm.

Arquivo: `anonymous.sh`, função `cleanup()` (linhas iniciais).

#### 5.4 Sleep interrompível (`nap` function)

```bash
nap() {
    sleep "$1" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""
}
```

`sleep` puro do bash **não responde a sinais até terminar**. Se o poll do mail é 5s e o usuário Ctrl+C, o watcher esperaria os 5s antes de reagir — visível como lag perceptível ao fechar o navegador. Rodando `sleep &` + `wait`, qualquer sinal dispara o trap imediatamente; o trap mata o `SLEEP_PID` e o script encerra em <100ms.

Arquivo: `anonymous-mail.sh`, função `nap()`.

---

### 6. Camada de e-mail descartável (mail.tm)

#### 6.1 Por que mail.tm

Critérios pro serviço: **free, sem API key, sem cadastro, REST público, deletável**. [mail.tm](https://mail.tm) bate todos:

- Gratuito, sem limite de contas (rate limit de 8 req/s, ok pra polling)
- Sem signup nem API key: `POST /accounts` cria e retorna ID na hora
- API REST documentada (Hydra-style; aceitamos JSON Accept header pra evitar envelope)
- `DELETE /accounts/{id}` apaga conta de verdade

Alternativas (Guerrilla Mail, 10minutemail) ou exigem API paga, ou retornam endereços já-spammed, ou bloqueiam Tor agressivamente.

Atribuição obrigatória nos termos: "Inbox by mail.tm" — incluída no banner que imprimimos.

#### 6.2 Provisioning: `/domains → /accounts → /token`

Três chamadas:

1. `GET /domains` — lista de domínios ativos no mail.tm (rotacionam de tempos em tempos). Pegamos o primeiro `isActive` via `jq`.
2. `POST /accounts {address, password}` — cria a conta. Address é `anon<12-random-chars>@<domain>`; password é 24 chars `[a-z0-9]`. Retries até 5x em HTTP 422 (colisão de address aleatoriamente).
3. `POST /token {address, password}` — autentica e retorna JWT. Salvamos no `.anon-mail` dentro do perfil.

Arquivo: `anonymous-mail.sh`, função `provision_fresh()`.

#### 6.3 Endereço e senha cripto-OK

```bash
LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c "$n"
```

Tanto address (`<12 chars>`) quanto password (`<24 chars>`) vêm de `/dev/urandom` — entropia de kernel, não `$RANDOM` do bash (que é cíclico e previsível). `LC_ALL=C` evita expansão de classes Unicode no `tr`, garantindo consistência cross-distro.

Arquivo: `anonymous-mail.sh`, função `rand_str()`.

#### 6.4 Polling em tempo real

mail.tm **não tem WebSocket público**. A solução é loop de polling de `GET /messages` a cada `ANON_MAIL_POLL` segundos (default 5; mínimo 2 — limite imposto pelo script pra não estourar rate limit). Default escolhido empiricamente: serviços de signup normalmente entregam e-mail em <10s; com poll 5s, latência média do usuário é ~7s entre disparar e ver no terminal.

Cada iteração compara IDs vistos (`SEEN`) com IDs retornados; imprime só os novos, em ordem cronológica (mail.tm devolve do mais novo pro mais antigo — invertemos).

Arquivo: `anonymous-mail.sh`, loop `while true; do ... done` final.

#### 6.5 Extração automática de código de verificação

99% dos signups mandam um número de 4–8 dígitos como código de OTP. Pra evitar o usuário precisar ler o corpo do e-mail manualmente, regexamos:

```bash
code="$(printf '%s' "$body $subj" | grep -Eo '[0-9]{4,8}' | head -n1)"
```

Procuramos no `subject` + `text`. Pega o primeiro match. Falsos positivos existem (ex: ano "2026" num footer), mas mostramos ao lado do código também ("Código provável: 1234") — usuário valida visualmente.

Arquivo: `anonymous-mail.sh`, função `print_message()`.

#### 6.6 Fallback HTML → text

Alguns sites enviam só `text/html`, sem `text/plain`. Quando `.text` vem vazio, fazemos:

```bash
body="$(jqr '(.html // []) | join("\n")' \
    | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g')"
```

Concatena os fragmentos HTML, remove tags via regex e desescapa entidades comuns. Não é parser HTML — é o suficiente pra extrair texto legível de e-mails transacionais (que tendem a HTML simples), não pra renderizar newsletter complexa.

Arquivo: `anonymous-mail.sh`, função `print_message()` (bloco do fallback).

#### 6.7 Refresh de token JWT

mail.tm expira tokens depois de algumas horas. Detectamos via `HTTP 401` no polling, chamamos `get_token()` (que faz `POST /token` com address+password salvos), regravamos as creds, e continuamos o loop **sem perder mensagens** (a próxima iteração re-lista tudo).

Arquivo: `anonymous-mail.sh`, dentro do `while true` — `if [[ "$RESP_CODE" == "401" ]]; then`.

#### 6.8 Rate limit (429) e erros transitórios

mail.tm rate-limit é 8 req/s. Em 429, esperamos extra 5s antes do próximo poll. Em 5xx ou rede caída (HTTP 000), silenciosamente continuamos — o próximo poll resolve. Não rompemos a sessão por blip de rede.

Arquivo: `anonymous-mail.sh`, mesmo loop.

#### 6.9 Auto-delete da conta no exit

Quando o perfil é **efêmero** (sem `KEEP`), o `cleanup()` do mail script faz `DELETE /accounts/{id}` antes de morrer. A conta deixa de existir no mail.tm. Casa com a filosofia geral: ao fechar o navegador, **nada** dessa identidade sobrevive.

Quando o perfil é persistente (`KEEP=X` ou caminho explícito via `$1`), **mantemos** a conta — mesma identidade volta na próxima sessão.

Arquivo: `anonymous-mail.sh`, função `cleanup()` (condicional `if PERSISTENT -eq 0`).

#### 6.10 Modo persistente: reutiliza endereço

Com `KEEP`, o mail script primeiro tenta `load_creds()` do `.anon-mail` do perfil. Se as creds estão lá e o token ainda valida (`get_token` retorna 200), reutiliza. Se o token expirou e o address ainda existe no mail.tm, renova só o token. Se o address foi deletado pelo mail.tm (acontece após dias de inatividade), cria conta nova com o mesmo padrão.

Arquivo: `anonymous-mail.sh`, bloco `# -------- provisiona ou recarrega --------`.

#### 6.11 Credenciais com mode 600

```bash
( umask 077
  jq -nc --arg address "$ADDRESS" ... > "$CRED_FILE" )
```

`umask 077` dentro de subshell garante que `.anon-mail` é criado com `rw-------` (mode 600). Sem isso, outros usuários no mesmo sistema poderiam ler o token JWT e drenar sua caixa de entrada.

Arquivo: `anonymous-mail.sh`, função `save_creds()`.

---

### 7. Camada cross-platform (`lib/platform.sh`)

#### 7.1 Detecção de SO e distro

```bash
case "$(uname -s)" in
    Linux)  GHOST_OS=linux ;;
    Darwin) GHOST_OS=macos ;;
```

Depois (só no Linux) lemos `/etc/os-release` e classificamos `ID` + `ID_LIKE` em três famílias: `debian`, `arch`, `fedora`. Distros derivadas (Ubuntu, Pop!_OS, Manjaro, Nobara, etc.) são detectadas via `ID_LIKE` — o script funciona em qualquer derivativo sem ajuste manual.

Arquivo: `lib/platform.sh`, funções `anon_os()` e `anon_linux_distro()`.

#### 7.2 Dispatch de package manager

```bash
anon_pkg_install() {
    case "$(anon_pkg_manager)" in
        apt)    sudo apt install -y "$@" ;;
        pacman) sudo pacman -S --noconfirm --needed "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        brew)   brew install "$@" ;;
    esac
}
```

Todos os comandos de instalação/remoção/check passam por essas funções. O `install.sh` chama `anon_pkg_install` agnóstico do package manager. Adicionar suporte a uma nova distro = uma linha na tabela.

`brew` no macOS dispensa `sudo` (intencional do Homebrew). `pacman --needed` evita reinstalar pacotes já presentes. `apt -y`/`dnf -y` aceitam confirmações automaticamente.

Arquivo: `lib/platform.sh`, funções `anon_pkg_*`.

#### 7.3 Dispatch de serviço (systemctl vs brew services)

```bash
anon_service_enable() {
    case "$(anon_os)" in
        linux) sudo systemctl enable --now "$1" ;;
        macos) brew services start "$1" ;;
    esac
}
```

No macOS, `brew services start` já persiste entre boots — não há "enable" separado, então `enable` = `start`. No Linux usamos `systemctl enable --now` que faz as duas operações de uma vez. Quem chama (`install.sh`) trata as duas plataformas com a mesma chamada.

Arquivo: `lib/platform.sh`, funções `anon_service_*`.

#### 7.4 Port-check portável (`nc -z`)

```bash
anon_port_open() {
    nc -z -w 2 "$1" "$2" >/dev/null 2>&1
}
```

`nc -z` (zero-I/O port scan) funciona em Linux (`netcat-openbsd`/`openbsd-netcat`/`nmap-ncat`) **e** macOS (BSD `nc`). Não usamos `/dev/tcp` porque o `/bin/bash` do macOS é 3.2.57 e **não tem suporte a `/dev/tcp`** — falharia silenciosamente.

`-w 2` é timeout de 2s. Tor responde em <100ms; se demorar 2s, algo está errado e queremos saber rápido.

Arquivo: `lib/platform.sh`, função `anon_port_open()`.

#### 7.5 Bash 3.2 portabilidade

`/bin/bash` no macOS é 3.2.57 (de 2007, último Apple-shipped antes do GPL3). Nada de:

- `mapfile` / `readarray` (bash 4+)
- `${var,,}` lowercase expansion (bash 4+)
- Associative arrays `declare -A` (bash 4+)
- `&>` redirect (bash 4+, embora tolerado)

Substituições que usamos:

| Em vez de... | Usamos... |
|---|---|
| `mapfile -t arr < file` | `arr=(); while IFS= read -r l; do arr+=("$l"); done < file` |
| `${var,,}` | `printf '%s' "$var" \| tr '[:upper:]' '[:lower:]'` |
| `[[ -v VAR ]]` | `[[ -n "${VAR:-}" ]]` |
| `read -d ''` | `IFS= read -r` em loop |

Arquivo: `lib/platform.sh` (comentários no header explicitam a restrição).

#### 7.6 `$TMPDIR` awareness

`/tmp` no Linux, `/var/folders/.../T/` no macOS (via `$TMPDIR`). Hardcoding `/tmp` quebraria o macOS. Função `anon_tmp_prefix()` retorna `${TMPDIR:-/tmp}` — `mktemp -d` aceita ambos.

Arquivo: `lib/platform.sh`, função `anon_tmp_prefix()`.

---

### 8. Camada de instalação (`install.sh`)

#### 8.1 Tracking rastreado de pacotes instalados

Tudo que `install.sh` instala é gravado em `~/.cache/anonymous-browser/installed-pkgs`, uma linha por pacote. `uninstall.sh` lê esse arquivo e só remove o que **nós** colocamos — nunca o que o usuário já tinha. Se você já tinha `curl` antes, ele continua depois do `uninstall.sh`.

Arquivo: `install.sh`, variável `PKG_TRACK_FILE`.

#### 8.2 Tags por origem (`pkg:`/`cask:`/`flatpak:`/`wrapper:`)

```
pkg:tor
pkg:python3-venv
cask:firefox        # legado macOS (não usado atualmente)
flatpak:com.brave...  # legado Pop!_OS
wrapper:/home/user/.local/bin/anonymous-browser
```

O prefixo permite o `uninstall.sh` dispatchar pra ferramenta certa: `brew uninstall --cask`, `flatpak uninstall --user`, `rm` direto pro wrapper, etc.

Arquivo: `install.sh` (escrita) + `uninstall.sh` (leitura por prefixo).

#### 8.3 Ubuntu Noble t64 transition detection

Ubuntu 24.04 (Noble) e Pop!_OS 24.04 fizeram a transição `time_t` para 64-bit em 32-bit ARMv7, renomeando dezenas de libs com sufixo `t64`:

- `libasound2` → `libasound2t64`
- `libgtk-3-0` → `libgtk-3-0t64`

Se você instala `libasound2` no Noble, o apt aceita (stub virtual), mas a versão real é `libasound2t64`. Detectamos qual é o pacote **real** (não-stub) via `apt-cache show ... | grep '^Filename:'`:

```bash
pick_pkg() {
    for cand in "$@"; do
        if apt-cache show "$cand" 2>/dev/null | grep -q '^Filename:'; then
            echo "$cand"; return 0
        fi
    done
}
LIBASOUND=$(pick_pkg libasound2t64 libasound2)
```

Pega o primeiro candidato com `Filename:` (pacote real). Funciona em Ubuntu 22.04 (escolhe `libasound2`) e 24.04 (escolhe `libasound2t64`).

Arquivo: `install.sh`, bloco do `case` `debian)`.

#### 8.4 Idempotência

Cada step do `install.sh` checa antes de agir:

- Pacotes: `anon_pkg_is_installed` antes de instalar
- Serviço Tor: `anon_service_is_active tor` antes de enable
- Venv: `[[ -d "$VENV" ]]` antes de criar
- Wrapper: `mkdir -p` e overwrite (sempre regenera, sem corromper estado)

Rodar `install.sh` 10 vezes seguidas é seguro. A segunda execução em diante imprime `[=]` ("já presente") pra cada step.

#### 8.5 Validação Tor no fim com endpoint Tor-friendly

Antes de declarar sucesso, `install.sh` testa Tor com `https://check.torproject.org/api/ip` (mesmo motivo que §1.5 — `ipinfo.io` foi removido como primário por ficar Cloudflare-blocked). Se a saída do exit responde com IP válido, marca tor como `[+]` no resumo final. Se falha, marca `[!]` mas **não aborta** — você pode estar atrás de DPI que precisa de bridges, e instalação continua.

Arquivo: `install.sh`, bloco `# -------- 4. validação final --------`.

#### 8.6 Wrapper local em `~/.local/bin` (skipável)

Por default, `install.sh` cria `~/.local/bin/anonymous-browser` apontando pra `$SCRIPT_DIR/anonymous.sh` (modo clone). Quando rodado via `npm` (que já forneceu o binário global), o launcher Node seta `ANON_SKIP_WRAPPER=1` antes de chamar `install.sh`, e essa step é pulada — evita dois `anonymous-browser` no PATH com mesma função.

Arquivo: `install.sh`, bloco `# -------- 4b. wrapper global --------`.

---

### 9. Camada de distribuição (npm shim)

#### 9.1 Por que Node como shim universal

`npm` é a forma mais ubíqua de instalar CLIs globais hoje (mais até que `brew` ou `cargo install` — todo dev tem npm). Mas o `anonymous-browser` é shell + Python. Solução: um shim Node em `bin/anonymous-browser.js` que **apenas** orquestra (`spawn('bash', [anonScript])`). Mantém shell como tecnologia primária; usa Node só pra distribuição.

Arquivo: `bin/anonymous-browser.js`.

#### 9.2 Lazy install (postinstall NÃO baixa Tor)

`postinstall.js` **só** corrige execbits dos `.sh` (npm às vezes preserva mode 644 do tarball). **Não** roda `install.sh`. Razão: `npm i -g` frequentemente roda como root (via `sudo`), e `install.sh` cria `~/.camoufox-venv` — que seria criado em `/root` por engano. Pior: `sudo npm i -g` em sistemas onde o usuário não passou `--unsafe-perm` falha em rodar postinstall scripts complexos.

Solução: na **primeira execução** de `anonymous-browser`, se `~/.camoufox-venv` não existe, o shim chama `install.sh` no usuário corrente. Aí sim ele tem `$HOME` certo e roda `sudo` interativamente quando necessário.

Arquivo: `bin/anonymous-browser.js`, bloco `if (!fs.existsSync(venv))`.

#### 9.3 TTY detection no prompt

```javascript
if (process.stdin.isTTY && process.stdout.isTTY) {
    const ans = await ask('[anonymous-browser] Quer e-mail temporário descartável? [y/N] ');
    ...
} else {
    process.env.MAIL = '0';
}
```

Em uso humano (terminal), pergunta sobre MAIL. Em scripts (stdin redirecionado de pipe/arquivo), assume `MAIL=0` e segue silenciosamente — não trava esperando input que nunca vem.

Arquivo: `bin/anonymous-browser.js`, função `(async () => ...)`.

#### 9.4 `chmod +x` best-effort

```javascript
for (const s of ['anonymous.sh', 'install.sh', 'new-tor-circuit.sh', 'anonymous-mail.sh']) {
    try { fs.chmodSync(path.join(pkgRoot, s), 0o755); } catch (_) {}
}
```

Tarball npm às vezes preserva execbits da source, às vezes não (depende da versão do npm e do registry). Em vez de confiar, o shim faz chmod logo no boot. `try/catch` ignora EPERM (sistema readonly, etc.).

Arquivo: `bin/anonymous-browser.js` (logo após `require`s).

#### 9.5 Signal propagation

Quando o usuário dá Ctrl+C no `anonymous-browser`, o sinal precisa chegar ao `anonymous.sh` (que tem o trap). Implementamos `spawn(..., { stdio: 'inherit' })` — o shell filho herda stdin/stdout, e Node propaga sinais. Quando o filho morre por sinal, repassamos:

```javascript
child.on('exit', (code, signal) => {
    if (signal) { process.kill(process.pid, signal); return; }
    process.exit(code == null ? 0 : code);
});
```

Sem isso, `anonymous-browser` retornaria exit 0 mesmo o shell tendo sido killed por SIGTERM — mascara o erro pro shell pai.

Arquivo: `bin/anonymous-browser.js`, `child.on('exit', ...)`.

---

### 10. Limitações honestas (o que **não** defendemos)

Todas as defesas acima cobrem **fingerprinting passivo** — o que sites veem de você sem cooperar com vendors anti-bot pagos. Existem vetores que esta stack **não** trata:

#### 10.1 TLS JA3 / JA4

A assinatura TLS ClientHello (cipher suites, extensões, ordem) revela "isso é Firefox real" vs "isso é Firefox patched". Camoufox **não** patcha o stack TLS — a JA3 dele é a de um Firefox normal, mas detectores comparando JA3 entre clientes podem notar. Solução real exige reescrever curl/openssl no nível abaixo do navegador — fora do escopo.

#### 10.2 HTTP/2 SETTINGS frame ordering

Mesmo princípio: a ordem de frames HTTP/2 que o browser manda na primeira conexão é fingerprintable. Camoufox segue Firefox upstream — coerente com `os="linux"` e levemente fora se você spoofou `os="macos"` (Firefox no macOS tem ordem ligeiramente diferente).

#### 10.3 Behavioral biometrics

Cadência de digitação, padrões de movimento de mouse, scroll velocity — Datadome, Akamai BMP, Kasada usam ML treinado em centenas de milhões de sessões pra distinguir humano de bot. `humanize=True` melhora vs detector ingênuo; não engana ML maduro.

#### 10.4 Enterprise bot management

Cloudflare Bot Management ($120k/ano), Datadome, PerimeterX, Shape (F5), Kasada — esses caras combinam TLS+HTTP/2+behavioral+device-graph. Se você precisa passar por isso, alternativas pagas: GoLogin, Multilogin, AdsPower (eles licenciam fingerprints reais via SDK proprietário). Não é o caso de uso desta stack.

#### 10.5 Mobile fingerprint

Camoufox upstream **não** suporta `os="ios"` nem `os="android"`. Tentar spoofar `User-Agent` de iPhone sem o resto (touch events, gyroscope, screen pixel ratio, dpr, sensor APIs) seria fingerprint imediatamente detectado como inconsistente. Removemos quaisquer presets mobile do código pra não dar falsa sensação.

#### 10.6 IP via WebRTC mDNS

Mesmo com `block_webrtc=True`, browsers modernos opcionalmente revelam IPs de mDNS local (`.local` addresses) via Network Information API em alguns contextos. Camoufox bloqueia o stack WebRTC inteiro como default, mas se o usuário (ou uma extensão) reativar via about:config, leak volta. **Não toque em `media.peerconnection.enabled`** se você se preocupa com isso.

#### 10.7 Frescor de User-Agent

A versão do Firefox que Camoufox spoofa segue o release do upstream Camoufox. Se Mozilla solta Firefox 142 e Camoufox ainda está em 135, seu UA dirá 135 enquanto humanos reais já estão em 142 — sinal fraco mas crescente. Mitigar: rodar `python -m camoufox fetch` mensalmente (manualmente; o `install.sh` puxa o latest mas não há auto-update entre rodadas).

#### 10.8 Network-level deanonymization

Esta stack rotaciona **identidade de aplicação** (IP, UA, fingerprint). **Não** protege contra adversário que observa o tráfego TLS ao redor do seu PC (ISP, rede corporativa, MITM com cert raiz instalado). Tor protege metadata de rede; se você precisa de privacidade contra adversário com cert root no seu device, problema é maior que browser fingerprint.

---

## Instalação

### Via npm (recomendado)

```bash
npm i -g anonymous-browser
```

Isso instala um comando `anonymous-browser` no seu PATH. Na primeira execução, ele dispara `install.sh` automaticamente — instala Tor + libs nativas via `sudo` (Linux) ou `brew` (macOS), cria o venv Python e baixa o binário Camoufox.

A cada execução depois disso, `anonymous-browser` pergunta se você quer um e-mail temporário descartável (`MAIL=1`) e abre o browser. Para pular o prompt, exporte `MAIL=0` ou `MAIL=1` antes.

### Via clone (modo dev)

`install.sh` detecta S.O. **e distro** automaticamente. Mesmo comando nas três famílias Linux principais e no macOS:

```bash
./install.sh
```

### Plataformas suportadas

| Família | Distros confirmadas | Package manager |
|---|---|---|
| Debian | Ubuntu, Pop!_OS, Debian, Mint | `apt` |
| Arch | Arch, Manjaro, EndeavourOS, CachyOS | `pacman` |
| Fedora | Fedora, Nobara, RHEL, Rocky, AlmaLinux | `dnf` |
| macOS | macOS 13+ | `brew` (Homebrew obrigatório) |

> Camoufox traz Firefox bundled — não há dependência de navegador do sistema. Em qualquer distro Linux com `tor`, `python3` e libs GTK/X11 básicas, o `anonymous.sh` funciona.

### Requisitos por S.O.

**Linux** — usa `sudo` na primeira execução pro package manager nativo (`apt`/`pacman`/`dnf`) e `systemctl`.

**macOS** — requer [Homebrew](https://brew.sh) **pré-instalado**; o `install.sh` orienta o usuário caso esteja faltando. Não usa `sudo` (brew dispensa root).

O `install.sh` é idempotente e fala muito. Ele instala (só o que falta):

- `tor` (proxy SOCKS5 em `127.0.0.1:9050`) — `systemd` no Linux, `brew services` no macOS
- Libs runtime do Camoufox (nomes diferem por distro: `libgtk-3-0t64` no Debian, `gtk3` no Arch/Fedora, etc.). macOS dispensa — Camoufox usa Firefox Cocoa nativo.
- venv Python em `~/.camoufox-venv` com `camoufox[geoip]`
- binário Camoufox (Firefox patched) + dataset GeoIP (~300 MB)
- valida saída Tor em endpoints Tor-friendly (`check.torproject.org`, `api.ipify.org`)

No fim, imprime um **resumo categorizado**: `[+]` instalado agora, `[=]` já presente, `[!]` falhou. Se algo está em `[!]`, [veja FIXES.md](FIXES.md) para diagnóstico.

### Configuração do ControlPort do Tor (opcional, mas recomendado)

Sem ControlPort 9051, `new-tor-circuit.sh` cai para um reload do serviço Tor — funciona mas é mais lento e fecha conexões em andamento. Para habilitar a troca rápida de circuito:

- **Linux**: edite `/etc/tor/torrc` adicionando `ControlPort 9051` + `CookieAuthentication 0`, depois `sudo systemctl restart tor`.
- **macOS**: `brew install tor` deixa apenas `torrc.sample`. Crie o `torrc` primeiro:
  ```bash
  cp "$(brew --prefix)/etc/tor/torrc.sample" "$(brew --prefix)/etc/tor/torrc"
  printf '\nControlPort 9051\nCookieAuthentication 0\n' >> "$(brew --prefix)/etc/tor/torrc"
  brew services restart tor
  ```

Reverter tudo:

```bash
./uninstall.sh
```

Remove venv, cache do Camoufox (XDG no Linux ou `~/Library/Caches/camoufox` no macOS), perfis temporários, e pergunta antes de remover pacotes (só o que foi rastreado em `~/.cache/anonymous-browser/installed-pkgs`). Se houver perfis persistentes em `~/.anonymous-browser/profiles/`, também pergunta interativamente antes de apagá-los.

---

## Uso

### Forma básica

```bash
./anonymous.sh                            # pergunta URL interativamente
./anonymous.sh https://site.com/signup    # one-liner
./anonymous.sh youtube.com                # esquema é opcional, prepende https://
```

Cada execução:

1. Detecta S.O. e inicia o Tor se ele estiver parado (`systemctl start tor` no Linux, `brew services start tor` no macOS).
2. Força novo circuito Tor (`SIGNAL NEWNYM` se ControlPort estiver aberto, senão reload do serviço).
3. Sorteia OS spoofado (`windows` | `macos` | `linux`).
4. Cria perfil descartável em `$TMPDIR/anon-XXXXXX` (`/tmp/...` no Linux, `/var/folders/.../anon-...` no macOS).
5. Abre Camoufox com fingerprint coerente + Tor + GPS negado silenciosamente.
6. Bloqueia até você fechar o navegador.
7. Apaga o perfil no exit (Ctrl+C, X do terminal, X do navegador, kill, crash — tudo).

### Receitas comuns

```bash
# padrão: Tor + OS aleatório + perfil descartável
./anonymous.sh https://site.com

# usando VPN própria (Mullvad, ProtonVPN paga, qualquer SOCKS5/HTTP)
PROXY=socks5://10.2.0.1:1080 ./anonymous.sh

# sem proxy (IP real, mas fingerprint trocado) — útil para sites internos
PROXY=none ./anonymous.sh

# força um OS específico (sem aleatório)
ANON_OS=macos ./anonymous.sh

# identidade persistente "trabalho" (cookies + OS fixos entre sessões)
KEEP=trabalho ./anonymous.sh https://gmail.com

# cria identidade nova com OS escolhido manualmente
KEEP=pessoal ANON_OS=windows ./anonymous.sh

# + e-mail descartável: imprime o endereço e mostra os e-mails
#   recebidos em tempo real NO MESMO terminal (útil pra código de verificação)
MAIL=1 ./anonymous.sh https://site.com/signup

# e-mail persistente junto da identidade persistente (mesmo endereço sempre)
MAIL=1 KEEP=trabalho ./anonymous.sh https://gmail.com

# se o exit Tor estiver bloqueado pelo Cloudflare do mail.tm, manda só o
# e-mail direto (o navegador continua via Tor):
MAIL=1 ANON_MAIL_PROXY=none ./anonymous.sh https://site.com/signup
```

### Variáveis de ambiente

| Variável | Valores | Efeito |
|---|---|---|
| `PROXY` | `tor` (default) \| `none` \| `socks5://host:port` \| `http://host:port` \| `https://host:port` | Sobrescreve o proxy Tor padrão. `none` desliga proxy (usa IP real). |
| `KEEP` | qualquer nome `[A-Za-z0-9_-]+` | Salva o perfil em `~/.anonymous-browser/profiles/<nome>/`. OS é fixado na primeira vez. Sem `KEEP`, o perfil é descartado no fim. |
| `ANON_OS` | `windows` \| `macos` \| `linux` (aceita maiúsculas; é normalizado para lowercase) | Força um OS específico (sem sorteio). Combinado com `KEEP`, fixa o OS persistente. |
| `USE_TOR` (legado) | `0` | Alias de `PROXY=none`. Mantido por compat com docs antigas. |
| `MAIL` | `1` | Gera um e-mail descartável (mail.tm) e mostra os recebidos em tempo real no mesmo terminal. Usa o mesmo `PROXY` e o mesmo perfil do navegador. Com `KEEP`, o endereço persiste entre sessões; sem `KEEP`, a conta é apagada no exit. |
| `ANON_MAIL_POLL` | segundos (default `5`, mínimo `2`) | Intervalo de checagem da caixa de entrada. |
| `ANON_MAIL_PROXY` | `tor` \| `none` \| `socks5://...` \| `http(s)://...` | Override de proxy **só pro e-mail** (o navegador segue no `PROXY`). Use `none` se o exit Tor estiver bloqueado pelo Cloudflare do mail.tm. |

> **E-mail descartável (`MAIL=1`):** o endereço é criado no [mail.tm](https://mail.tm) — serviço **gratuito, sem API key e sem cadastro** (rate limit 8 req/s). _Inbox by mail.tm._ Como qualquer serviço de e-mail temporário, **não use para nada sensível**: as mensagens são públicas pra quem souber o endereço. Conta efêmera é deletada ao fechar o navegador / Ctrl+C.

> **Tor × Cloudflare no mail.tm:** o `MAIL=1` roteia as chamadas pelo mesmo Tor do navegador (consistência de IP). Exit nodes Tor às vezes levam desafio do Cloudflare e a criação da caixa falha — o `anonymous-mail.sh` avisa e segue **sem derrubar o navegador**. Soluções: `./new-tor-circuit.sh` (troca o exit) ou `MAIL=1 ANON_MAIL_PROXY=none ./anonymous.sh ...` (e-mail direto, navegador ainda via Tor).

> **Schemes de proxy aceitos:** `socks5://`, `http://`, `https://`. O Playwright (engine do Camoufox) não suporta `socks4://` oficialmente — usar `socks4://` resulta em erro do Camoufox.

> **Privacidade com `PROXY=none`:** quando você desliga o proxy, o `anonymous.sh` também desativa `geoip` automaticamente. Sem isso, Camoufox tentaria buscar seu IP real em `api.ipify.org` (ou fallback) para casar locale/timezone — o que vazaria o IP que você quer esconder. Trade-off: sem `geoip`, locale/timezone do Firefox podem não bater com sua região, mas seu IP real fica em casa.

> **Perfil persistente em paralelo:** Firefox usa um arquivo `parent.lock` dentro do `user_data_dir`. Rodar `KEEP=foo ./anonymous.sh` duas vezes simultaneamente faz a segunda instância travar com timeout. Use nomes diferentes (`KEEP=foo` + `KEEP=bar`) para rodar em paralelo.

### Helpers

- **`./new-tor-circuit.sh`** — força IP novo entre execuções. Já é chamado pelo `anonymous.sh` quando o proxy é Tor. Pra rodar standalone, abra `ControlPort 9051` no torrc (caminho depende do S.O. — Linux: `/etc/tor/torrc`; macOS: `$(brew --prefix)/etc/tor/torrc`). Veja a seção "Configuração do ControlPort do Tor" acima.
- **`./anonymous-mail.sh`** — e-mail descartável com leitura em tempo real, standalone (sem abrir navegador). Imprime o endereço e fica mostrando os e-mails recebidos. Aceita `PROXY`, `ANON_MAIL_PROXY`, `ANON_MAIL_POLL` e `KEEP` (endereço persistente, mesmo padrão de perfil do `anonymous.sh`). Já é disparado automaticamente por `MAIL=1 ./anonymous.sh`. _Inbox by mail.tm._

---

## Validar que funcionou

Abre essas URLs **dentro** da janela aberta pelo `anonymous.sh`:

| Site | O que checar |
|---|---|
| [check.torproject.org](https://check.torproject.org) | IP é exit Tor (a badge verde "Congratulations" só aparece no Tor Browser oficial; aqui o que importa é o IP retornado bater com o de saída) |
| [ipinfo.io/json](https://ipinfo.io/json) | IP, país, ASN do exit |
| [browserleaks.com/javascript](https://browserleaks.com/javascript) | `navigator.platform`, screen, UA — devem casar com OS sorteado |
| [browserleaks.com/webgl](https://browserleaks.com/webgl) | `UNMASKED_VENDOR/RENDERER` — Camoufox spoofa coerente |
| [browserleaks.com/fonts](https://browserleaks.com/fonts) | Lista de fontes do OS spoofado, não do seu Linux real |
| [browserleaks.com/geo](https://browserleaks.com/geo) | "Permission denied" — GPS negado sem prompt |
| [abrahamjuliot.github.io/creepjs](https://abrahamjuliot.github.io/creepjs/) | **Trust Score >70% e zero "lies"** — métrica de ouro |
| [amiunique.org/fingerprint](https://amiunique.org/fingerprint) | Entropia / unicidade |

Validar IP no terminal:

```bash
curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
# {"IsTor":true,"IP":"107.189.5.121"}
```

---

## Comparação: anonymous-browser vs Tor Browser

| | `anonymous-browser` (este repo) | Tor Browser oficial |
|---|---|---|
| Engine | Camoufox (Firefox patched em C++) | Firefox ESR + patches Tor |
| Filosofia | Você finge ser outro device | Você se uniformiza com todo mundo |
| Troca UA | ✅ | n/a (todos têm o mesmo) |
| Troca `navigator.platform` | ✅ | ✅ (mas todo mundo tem o mesmo) |
| Troca WebGL/canvas/audio/fonts | ✅ coerente via BrowserForge | ✅ via resistFingerprinting (zeros) |
| Client Hints (`Sec-CH-UA-*`) | ✅ | ✅ |
| Geo/timezone casados com IP | ✅ (`geoip=True`) | uniforme |
| Proxy customizado (VPN, etc.) | ✅ (`PROXY=socks5://...`) | ❌ (só Tor) |
| Identidade persistente entre sessões | ✅ (`KEEP=nome`) | ❌ (sempre descartável) |
| Perfis mobile | ❌ (Camoufox não suporta) | ❌ |
| Passa em CreepJS | ✅ Trust >70% típico | ✅ Trust ~80% (homogêneo) |
| Dependências | apt + venv (~300 MB) | bundle pronto |

**Use `anonymous.sh`** quando quiser **identidade trocada** (parecer outra pessoa específica, com cookies/sessão controláveis). Use **Tor Browser** quando quiser **anonimato uniforme** (se misturar com a multidão, sem variação entre você e os outros usuários).

---

## Estrutura

```
anonymous-browser/
├── README.md              # este arquivo
├── FIXES.md               # histórico de bugs corrigidos (todos fechados)
├── LICENSE                # MIT
├── logo.jpg               # mascote (fantasma minimalista, mono)
├── .gitignore
├── install.sh             # auto-detecta S.O. + distro Linux (Debian/Arch/Fedora);
│                          # instala Tor, libs Camoufox, venv Python; resumo [+]/[=]/[!] no fim
├── uninstall.sh           # remove venv/cache/perfis; pergunta antes de remover pacotes;
│                          # também pergunta antes de apagar perfis persistentes em ~/.anonymous-browser/
├── anonymous.sh               # ★ super-comando: PROXY/KEEP/ANON_OS via env, Camoufox+Tor por default
├── new-tor-circuit.sh     # força SIGNAL NEWNYM (ControlPort 9051) ou reload do serviço
├── anonymous-mail.sh          # e-mail descartável (mail.tm) + leitura em tempo real no terminal
└── lib/platform.sh        # detecção de S.O. + distro + dispatch de package manager
                           # (apt/pacman/dnf/brew); bash 3.2 portable

# estado (não versionado):
~/.anonymous-browser/profiles/  # perfis persistentes criados por KEEP=nome
~/.camoufox-venv/           # venv com Camoufox + BrowserForge + GeoIP
~/.cache/anonymous-browser/     # track-file de pacotes instalados pelo install.sh
```

---

## Limitações & honestidade

1. **Não é silver bullet.** Anti-bot enterprise (Cloudflare BM, DataDome) detecta Camoufox via TLS/HTTP-2 fingerprint. Esta stack mira tracking publicitário e cadastros normais — não nações-estado, não Akamai-fronted login flows.
2. **Tor é lento.** Em média 5–15s pra primeira requisição. Cloudflare desafia exit nodes. Se um site bloquear, troque por VPN própria: `PROXY=socks5://seu-vpn:1080 ./anonymous.sh`.
3. **User-Agents envelhecem.** O Camoufox/BrowserForge atualizam UAs automaticamente. Pra puxar o dataset mais recente: `source ~/.camoufox-venv/bin/activate && python -m camoufox fetch`.
4. **Mullvad Browser e Tor Browser homogeneízam, não personificam.** Útil pra ler anonimamente, inútil pra cadastrar como "outro alguém".
5. **WebRTC permanece bloqueado pelo Camoufox** (`block_webrtc=True`) mesmo com `PROXY=none`, mas DNS lookups vão pelo seu resolver local — sua máquina aparece como Linux normal para o ISP nesse modo.
6. **Camoufox não emula iPhone/Android.** Documentação oficial só aceita `os="windows"|"macos"|"linux"`. Pra mobile coerente, alternativas pagas: GoLogin, Multilogin, AdsPower.

---

## Troubleshooting

### Perfil persistente não abre depois de um crash / `kill -9`

Firefox deixa um `parent.lock` (e/ou `.parentlock`) dentro do `user_data_dir`. Se você matou o processo no `kill -9` ou o sistema travou, o lock fica órfão e a próxima execução fica esperando.

```bash
# checar
ls -la ~/.anonymous-browser/profiles/<nome>/ | grep -i lock
# limpar (com o anonymous.sh fechado)
rm -f ~/.anonymous-browser/profiles/<nome>/parent.lock \
      ~/.anonymous-browser/profiles/<nome>/.parentlock
```

### Tor não sobe / `[!] Tor não responde em 127.0.0.1:9050`

```bash
# Linux
sudo systemctl status tor
sudo systemctl restart tor
journalctl -u tor@default | tail -20

# macOS
brew services info tor
brew services restart tor
```

Se o ISP está bloqueando Tor, use `PROXY=socks5://seu-vpn:1080 ./anonymous.sh` com uma VPN.

### `[!] PROXY inválido` mas o valor parece correto

Confira os schemes aceitos: `tor`, `none`, `socks5://`, `http://`, `https://`. `socks4://` não é suportado pelo Playwright.

### Camoufox `InvalidIP: Failed to get IP address` com proxy custom

Significa que o proxy custom (VPN/SOCKS) não está respondendo. Teste manualmente:

```bash
curl -s --socks5-hostname <vpn-host>:<port> https://api.ipify.org
```

Se não retorna IP, o proxy está fora. Volte ao Tor (`PROXY=tor`) ou conserte o VPN.

---

## Bugs conhecidos

Nenhum em aberto até 12/05/2026. Os 3 bugs originais (teste de Tor com `ipinfo.io`, ausência de Chromium em Pop!_OS sem snap, `TypeError` do Camoufox 0.4.11) estão **todos fechados** — histórico técnico completo em [FIXES.md](FIXES.md).

Se algo quebrar depois de uma atualização do Camoufox, Firefox ou Tor: abra issue no GitHub com o stacktrace e o resumo do `./install.sh`.

---

## Manifesto curto

Privacy não é sobre esconder. É sobre **escolher** o que mostrar, pra quem, e quando. Sites que coletam fingerprint sem te perguntar quebraram esse contrato primeiro. Esta ferramenta é uma resposta proporcional.

Não promove fraude. Não burla mecanismos de pagamento. Não invade sistemas. Faz uma coisa só: te devolve o controle de qual identidade seu browser apresenta ao internet.

A legalidade depende de jurisdição e de termos-de-uso do destino. Em quase todos os lugares civilizados, **trocar UA, IP e fingerprint é permitido**. Burlar ToS é cinza. Fraude documental é crime — em qualquer lugar, com ou sem esta ferramenta. **Você é o operador, você assume as consequências.** Esta linha não tem como ser apagada por boa intenção do dev.

---

## Inspirações & afins

- [Tor Project](https://www.torproject.org/) — o original
- [Camoufox](https://github.com/daijro/camoufox) — Firefox C++ patched, faz o trabalho pesado
- [BrowserForge](https://github.com/daijro/browserforge) — fingerprints coerentes
- [EFF Privacy Badger](https://privacybadger.org/), [uBlock Origin](https://ublockorigin.com/), [Mullvad VPN](https://mullvad.net/)
- [Cypherpunks Manifesto](https://www.activism.net/cypherpunk/manifesto.html), [Crypto Anarchist Manifesto](https://www.activism.net/cypherpunk/crypto-anarchy.html)
- [EFF Cover Your Tracks](https://coveryourtracks.eff.org/) — entenda o quanto você vaza

---

## Licença

MIT. Faça fork. Faça merge. Mande PR. Mande issue. Se algo quebrar com uma atualização do Camoufox/Firefox, abra issue com o stacktrace — esta stack vai precisar de manutenção contínua porque o lado adversário também não dorme.

> "If privacy is outlawed, only outlaws will have privacy."
> — Phil Zimmermann (criador do PGP)
