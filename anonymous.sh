#!/usr/bin/env bash
# anonymous.sh — super-comando do anonymous-browser
#
# Pergunta a URL de cadastro, força novo circuito Tor (se Tor for o proxy),
# abre Camoufox com OS spoofado (aleatório por default, ou via $ANON_OS),
# nega geolocalização silenciosamente e apaga tudo (perfil temporário + browser)
# quando o usuário:
#   - fechar a janela do navegador
#   - apertar Ctrl+C no terminal
#   - fechar a janela do terminal
#
# Uso:
#   ./anonymous.sh                                  # pergunta a URL
#   ./anonymous.sh https://site/signup              # passa URL direto
#
# Env vars (todas opcionais):
#   PROXY    tor (default) | none | socks5://host:port | http://host:port | etc.
#   KEEP     nome do perfil persistente em ~/.anonymous-browser/profiles/<nome>/
#            (descartável se vazio). OS é fixado na primeira vez.
#   ANON_OS windows | macos | linux. Força um OS específico (sem sorteio).
#   USE_TOR  0 = alias de PROXY=none (compat com docs antigas)
#   MAIL     1 = gera e-mail descartável e mostra os recebidos em tempo real
#            no mesmo terminal (via anonymous-mail.sh; usa o mesmo PROXY/perfil).
#   ANON_MAIL_POLL   intervalo de polling do e-mail em segundos (default 5)
#   ANON_MAIL_PROXY  override de proxy só pro e-mail (ex.: none se o exit
#                     Tor estiver bloqueado pelo Cloudflare do mail.tm)
#
# Licença: MIT — veja LICENSE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

VENV="$HOME/.camoufox-venv"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

# Inteiro uniforme em [0, max-1] via /dev/urandom.
# Bash $RANDOM tem só 15 bits e PRNG seedável previsivelmente; aqui sorteamos
# OS spoofado, então usar a mesma fonte de entropia do resto do projeto.
rand_int() {
    local max="$1"
    local n
    n="$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')"
    echo $(( n % max ))
}

# First-party isolation: opcional, isola cookies/storage por origem top-level.
# Trade-off: quebra "login com Google" cross-site (que pra essa stack é feature).
if [[ "${FIRSTPARTY_ISOLATE:-0}" == "1" ]]; then
    export ANON_FIRSTPARTY_ISOLATE=1
else
    export ANON_FIRSTPARTY_ISOLATE=0
fi

# -------- cleanup robusto: INT, TERM, HUP, EXIT --------
TMP=""
PERSISTENT=0
MAIL_PID=""
cleanup() {
    local rc=$?
    # Encerra o watcher de e-mail; o trap dele apaga a conta efêmera no mail.tm.
    if [[ -n "$MAIL_PID" ]]; then
        kill "$MAIL_PID" 2>/dev/null || true
        wait "$MAIL_PID" 2>/dev/null || true
    fi
    # Só apaga TMP se NÃO for perfil persistente.
    if [[ -n "$TMP" && -d "$TMP" && "$PERSISTENT" -eq 0 ]]; then
        rm -rf "$TMP"
    fi
    exit $rc
}
trap cleanup INT TERM HUP EXIT

# -------- pré-checks --------
OS_KIND="$(anon_os)" || { echo "[!] S.O. não suportado"; exit 1; }

if [[ ! -d "$VENV" ]]; then
    echo "[!] venv Camoufox não encontrado em $VENV"
    echo "    Rode primeiro: ./install.sh"
    exit 1
fi

if [[ ! -x "$SCRIPT_DIR/new-tor-circuit.sh" ]]; then
    echo "[!] new-tor-circuit.sh não encontrado/executável em $SCRIPT_DIR"
    exit 1
fi

# -------- resolve PROXY --------
# Compat: USE_TOR=0 vira PROXY=none se PROXY não foi setado explicitamente.
if [[ -z "${PROXY:-}" && "${USE_TOR:-1}" == "0" ]]; then
    PROXY="none"
fi

case "${PROXY:-}" in
    ""|tor)
        PROXY_URL="socks5://127.0.0.1:9050"
        USE_TOR_INTERNAL=1
        PROXY_LABEL="Tor"
        ;;
    none)
        PROXY_URL=""
        USE_TOR_INTERNAL=0
        PROXY_LABEL="nenhum (IP real)"
        ;;
    # Playwright (engine do Camoufox) só suporta oficialmente socks5, http, https.
    socks5://*|http://*|https://*)
        PROXY_URL="$PROXY"
        USE_TOR_INTERNAL=0
        PROXY_LABEL="custom"
        ;;
    *)
        echo "[!] PROXY inválido: '$PROXY'"
        echo "    Aceitos: tor (default) | none | socks5://host:port | http://host:port | https://host:port"
        exit 1
        ;;
esac

# -------- resolve KEEP (perfil persistente) --------
PROFILE_DIR=""
if [[ -n "${KEEP:-}" ]]; then
    if [[ ! "$KEEP" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "[!] KEEP inválido: '$KEEP'"
        echo "    Use apenas letras, números, '_' e '-' (sem '.', '/', espaços)."
        exit 1
    fi
    PROFILE_DIR="$HOME/.anonymous-browser/profiles/$KEEP"
    mkdir -p "$PROFILE_DIR"
    PERSISTENT=1
fi

# -------- resolve ANON_OS --------
OS_LIST=(windows macos linux)
OS_FILE=""
[[ -n "$PROFILE_DIR" ]] && OS_FILE="$PROFILE_DIR/.anon-os"

if [[ -n "${ANON_OS:-}" ]]; then
    # Camoufox aceita apenas lowercase ('windows'/'macos'/'linux'); tolera erro
    # do usuário ('Windows', 'MacOS', etc.). tr é portable em bash 3.2 (macOS).
    ANON_OS_LOWER="$(printf '%s' "$ANON_OS" | tr '[:upper:]' '[:lower:]')"
    case "$ANON_OS_LOWER" in
        windows|macos|linux) OS_RAND="$ANON_OS_LOWER" ;;
        *)
            echo "[!] ANON_OS inválido: '$ANON_OS'"
            echo "    Aceitos: windows | macos | linux"
            exit 1
            ;;
    esac
    OS_SOURCE="forçado via ANON_OS"
    [[ -n "$OS_FILE" ]] && printf '%s\n' "$OS_RAND" > "$OS_FILE"
elif [[ -n "$OS_FILE" && -s "$OS_FILE" ]]; then
    OS_RAND="$(tr -d '[:space:]' < "$OS_FILE")"
    case "$OS_RAND" in
        windows|macos|linux) ;;
        *)
            echo "[!] $OS_FILE corrompido (valor: '$OS_RAND'). Apague ou corrija."
            exit 1
            ;;
    esac
    OS_SOURCE="persistido em $OS_FILE"
else
    OS_RAND="${OS_LIST[$(rand_int ${#OS_LIST[@]})]}"
    OS_SOURCE="aleatório"
    if [[ -n "$OS_FILE" ]]; then
        printf '%s\n' "$OS_RAND" > "$OS_FILE"
        OS_SOURCE="aleatório (salvo em $OS_FILE)"
    fi
fi

# -------- garante Tor up se for usar Tor --------
if [[ "$USE_TOR_INTERNAL" -eq 1 ]]; then
    if ! anon_service_is_active tor; then
        echo "[anon] iniciando Tor ($OS_KIND)..."
        anon_service_start tor 2>/dev/null || true
        sleep 3
    fi
fi

# -------- pede URL (aceita também via $1) --------
URL="${1:-}"
if [[ -z "$URL" ]]; then
    read -r -p "[anon] URL de cadastro: " URL
fi
if [[ -z "$URL" ]]; then
    echo "[!] URL vazia, abortando."
    exit 1
fi
# se faltou esquema, prepende https://
if [[ ! "$URL" =~ ^https?:// ]]; then
    URL="https://$URL"
fi

# -------- novo circuito Tor (só se Tor) --------
# new-tor-circuit.sh devolve 0=NEWNYM ok, 1=HUP fallback, 2=falhou.
# STRICT_CIRCUIT=1 aborta a sessão se NEWNYM não funcionou — usar quando
# qualquer reuso de circuito é inaceitável (ex: investigação forense
# sensível a IP de saída).
if [[ "$USE_TOR_INTERNAL" -eq 1 ]]; then
    echo "[anon] forçando novo circuito Tor..."
    set +e
    "$SCRIPT_DIR/new-tor-circuit.sh"
    CIRCUIT_RC=$?
    set -e
    case "$CIRCUIT_RC" in
        0) ;;  # confirmado
        1) warn "circuito renovado via HUP fallback (ControlPort indisponível)." ;;
        *)
            err "falha ao renovar circuito Tor — continuando com circuito atual."
            if [[ "${STRICT_CIRCUIT:-0}" == "1" ]]; then
                err "STRICT_CIRCUIT=1: abortando."
                exit 1
            fi
            ;;
    esac
fi

# -------- resolve IP de saída para geoip (não delega ao Camoufox) --------
# Camoufox com geoip=True probe api.ipify.org / ipinfo.io / checkip.amazonaws.com
# — TODOS bloqueados pelo Cloudflare quando origem é exit Tor (HTTP 403/vazio),
# o que faz camoufox/ip.py:119 levantar InvalidIP e o browser nunca abrir.
# Resolvemos o IP aqui, num endpoint Tor-friendly (check.torproject.org), e
# passamos o IP em string pro Camoufox — que aceita geoip=<ip> e pula o probe.
GEOIP_VALUE=""
if [[ -n "$PROXY_URL" ]]; then
    CURL_PROXY_ARGS=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && CURL_PROXY_ARGS+=("$line")
    done < <(anon_curl_proxy_args "$PROXY_URL" || true)

    # Ordem: Tor-API primeiro (purpose-built, nunca bloqueia), depois fallbacks
    # caso o proxy não seja Tor.
    for ep in \
        "https://check.torproject.org/api/ip" \
        "https://icanhazip.com" \
        "https://ifconfig.co/ip" \
        "https://ipecho.net/plain"
    do
        RESP="$(curl -s --max-time 8 \
            ${CURL_PROXY_ARGS[@]+"${CURL_PROXY_ARGS[@]}"} \
            "$ep" 2>/dev/null || true)"
        [[ -z "$RESP" ]] && continue
        case "$ep" in
            *torproject.org*) IP="$(printf '%s' "$RESP" | jq -r '.IP // empty' 2>/dev/null || true)" ;;
            *)                IP="$(printf '%s' "$RESP" | tr -d '[:space:]')" ;;
        esac
        if [[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ || "$IP" == *:* ]]; then
            GEOIP_VALUE="$IP"
            break
        fi
    done

    if [[ -n "$GEOIP_VALUE" ]]; then
        echo "[anon] IP geoip: $GEOIP_VALUE ($PROXY_LABEL)"
    else
        echo "[anon] geoip : não consegui resolver IP via proxy — abrindo sem geoip"
        echo "         (timezone/locale podem ficar inconsistentes com o IP de saída)"
    fi
fi

# -------- perfil descartável OU persistente --------
if [[ "$PERSISTENT" -eq 1 ]]; then
    TMP="$PROFILE_DIR"
    PROFILE_LABEL="$TMP (PERSISTENTE — não será apagado)"
else
    # $TMPDIR no macOS (/var/folders/.../T); /tmp no Linux. mktemp aceita.
    TMP="$(mktemp -d "$(anon_tmp_prefix)/anon-XXXXXX")"
    PROFILE_LABEL="$TMP (descartável)"
fi

echo "[anon] OS spoof : $OS_RAND ($OS_SOURCE)"
if [[ -n "$PROXY_URL" ]]; then
    echo "[anon] proxy   : $PROXY_URL ($PROXY_LABEL)"
else
    echo "[anon] proxy   : $PROXY_LABEL — geoip desativado pra não vazar IP real"
fi
echo "[anon] perfil  : $PROFILE_LABEL"
echo "[anon] URL     : $URL"

# -------- e-mail descartável em tempo real (opt-in: MAIL=1) --------
# Roda anonymous-mail.sh em background reaproveitando o mesmo proxy e o mesmo
# diretório de perfil; ele imprime o endereço e os e-mails no mesmo terminal.
# cleanup() mata esse PID ao fechar o browser/Ctrl+C (e ele apaga a conta).
if [[ "${MAIL:-0}" == "1" ]]; then
    if [[ -f "$SCRIPT_DIR/anonymous-mail.sh" ]]; then
        ANON_PROXY_URL="$PROXY_URL" ANON_PROXY_RESOLVED=1 \
        ANON_MAIL_PROFILE="$TMP" ANON_MAIL_PERSISTENT="$PERSISTENT" \
            bash "$SCRIPT_DIR/anonymous-mail.sh" &
        MAIL_PID=$!
    else
        echo "[!] MAIL=1 mas anonymous-mail.sh não encontrado — seguindo sem e-mail."
    fi
fi

# -------- dispara Camoufox --------
# shellcheck source=/dev/null
source "$VENV/bin/activate"

python - <<PY
import os
import signal, sys
from camoufox.sync_api import Camoufox
from browserforge.fingerprints import Screen

# encerra limpo em SIGHUP/SIGTERM (SIGINT já vira KeyboardInterrupt)
for s in (signal.SIGHUP, signal.SIGTERM):
    signal.signal(s, lambda *_: sys.exit(0))

URL        = "$URL"
OS_ARG     = "$OS_RAND"
UDD        = "$TMP"
PROXY_URL  = "$PROXY_URL"
GEOIP_VAL  = "$GEOIP_VALUE"

screens = {
    "windows": Screen(max_width=1920, max_height=1080),
    "macos":   Screen(max_width=2560, max_height=1600),
    "linux":   Screen(max_width=1920, max_height=1080),
}

proxy_arg = {"server": PROXY_URL} if PROXY_URL else None
# geoip:
#   - sem proxy → False (privacidade: não vaza IP real pra api de geoip)
#   - com proxy + IP resolvido pelo bash → string explícita (Camoufox pula o
#     probe interno em api.ipify.org/ipinfo.io etc., que são Cloudflare-blocked
#     pra exits Tor e fariam o launch quebrar com InvalidIP)
#   - com proxy mas sem IP (todos endpoints caíram) → False com aviso
if proxy_arg is None:
    geoip_kw = False
elif GEOIP_VAL:
    geoip_kw = GEOIP_VAL
else:
    geoip_kw = False

print(f"[anon] abrindo Camoufox como '{OS_ARG}' -> {URL}")

# Defaults defensivos explícitos: não confiar só nos defaults do Camoufox.
# Cada pref é uma defesa em profundidade contra um vetor específico — se
# Camoufox upstream regredir, ainda estamos cobertos.
firefox_user_prefs = {
    # Geo: negar sem prompt (prompt em si já é fingerprint).
    "permissions.default.geo": 2,
    "geo.enabled": False,

    # WebRTC: stack inteira off, não só block_webrtc do Camoufox.
    "media.peerconnection.enabled": False,
    "media.peerconnection.ice.default_address_only": True,
    "media.peerconnection.ice.no_host": True,

    # DNS: sempre via proxy, nunca DoH (que vaza pra Cloudflare/Google).
    "network.proxy.socks_remote_dns": True,
    "network.trr.mode": 5,  # DoH explicitamente off
    "network.dns.disablePrefetch": True,
    "network.dns.disablePrefetchFromHTTPS": True,
    "network.predictor.enabled": False,
    "network.prefetch-next": False,

    # Safebrowsing: round-trip pra Mozilla/Google a cada page load.
    "browser.safebrowsing.malware.enabled": False,
    "browser.safebrowsing.phishing.enabled": False,
    "browser.safebrowsing.downloads.enabled": False,
    "browser.safebrowsing.downloads.remote.enabled": False,

    # APIs de hardware: reduz superfície de fingerprint.
    "dom.battery.enabled": False,
    "dom.gamepad.enabled": False,
    "dom.vr.enabled": False,

    # Vazamento por digitação na urlbar (autocomplete envia pra search engine).
    "browser.search.suggest.enabled": False,
    "browser.urlbar.suggest.searches": False,
    "browser.urlbar.suggest.history": False,
    "browser.urlbar.suggest.bookmark": False,
    "browser.urlbar.speculativeConnect.enabled": False,

    # Telemetria Mozilla.
    "toolkit.telemetry.enabled": False,
    "toolkit.telemetry.unified": False,
    "toolkit.telemetry.archive.enabled": False,
    "datareporting.healthreport.uploadEnabled": False,
    "datareporting.policy.dataSubmissionEnabled": False,
    "app.shield.optoutstudies.enabled": False,

    # Captive portal / connectivity service: requests periódicos pra Mozilla.
    "network.captive-portal-service.enabled": False,
    "network.connectivity-service.enabled": False,

    # Push notifications: desnecessárias em sessão descartável.
    "dom.push.enabled": False,
    "dom.webnotifications.enabled": False,
}

if os.environ.get("ANON_FIRSTPARTY_ISOLATE") == "1":
    firefox_user_prefs.update({
        "privacy.firstparty.isolate": True,
        "privacy.firstparty.isolate.restrict_opener_access": True,
    })

with Camoufox(
    os=OS_ARG,
    headless=False,
    humanize=True,
    geoip=geoip_kw,
    proxy=proxy_arg,
    screen=screens[OS_ARG],
    user_data_dir=UDD,
    # True => Camoufox usa launch_persistent_context() (aceita user_data_dir).
    # Sem isso, Playwright reclama: "launch() got unexpected kwarg user_data_dir".
    # Cleanup permanece: bash trap apaga $TMP se PERSISTENT=0.
    persistent_context=True,
    firefox_user_prefs=firefox_user_prefs,
) as browser:
    # persistent_context=True devolve BrowserContext (não Browser).
    # BrowserContext.new_page() existe normalmente em Playwright.
    page = browser.new_page()
    # Tor pode estar lento ou com exit ruim — 60s evita matar a sessão por timeout
    # de navegação; mesmo que goto falhe, a janela continua aberta pro usuário
    # decidir (recarregar, trocar circuito, ou Ctrl+C).
    try:
        page.goto(URL, timeout=60_000)
    except Exception as e:
        print(f"[anon] aviso: page.goto falhou ({type(e).__name__}: {e})")
        print(f"[anon] janela aberta mesmo assim — tente recarregar ou Ctrl+C")
    try:
        # bloqueia até o usuário fechar o navegador inteiro (todas as janelas).
        # Context emite "close" quando o processo Firefox encerra.
        browser.wait_for_event("close", timeout=0)
    except (KeyboardInterrupt, SystemExit):
        pass
PY
