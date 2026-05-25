# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
Versionamento: [Semantic Versioning](https://semver.org/lang/pt-BR/)

## [Unreleased]

## [0.2.0] - 2026-05-24

### Added
- Defaults defensivos completos em `firefox_user_prefs` (DoH off, safebrowsing
  off, DNS via proxy, WebRTC stack inteira off, battery/gamepad/VR APIs off,
  urlbar suggestions off, telemetria off, captive portal off, push off).
- Opt-in `FIRSTPARTY_ISOLATE=1` para per-site identity isolation (cookies/
  storage isolados por origem top-level).
- Opt-in `STRICT_CIRCUIT=1` para abortar a sessão se `NEWNYM` falhar (em vez
  de seguir silenciosamente com circuito reutilizado).
- `requirements.txt` com pinning de Camoufox (`>=0.4.11,<0.5.0`) — evita
  breaking change silencioso do upstream.
- `CHANGELOG.md` e `SECURITY.md` na raiz.
- Seção "O que ESTE projeto NÃO protege contra" no README (threat model
  honesto), além de FAQ e Troubleshooting.
- Reporta versão exata do Camoufox instalado ao final do `install.sh`.

### Changed
- `$RANDOM` substituído por `/dev/urandom` (via `rand_int()`) em todos os
  sorteios. Mesma fonte de entropia que `rand_str()` já usava.
- `new-tor-circuit.sh` agora devolve exit codes diferenciados:
  `0` = `NEWNYM` confirmado, `1` = HUP/reload fallback, `2` = falha total.
  `anonymous.sh` passa a checar o código em vez de engolir com `|| true`.

### Fixed
- Comando `cd ghost-browser` no README (era resíduo do rename para
  `anonymous-browser`).

## [0.1.0] - 2026-05-24

### Added
- Release inicial: CLI Bash que monta Camoufox + Tor + perfil descartável
  por sessão, com OS spoofado coerente, geo via MaxMind, suporte opcional a
  e-mail descartável em tempo real via mail.tm, identidade persistente via
  `KEEP=`, e suporte a Linux (Debian/Arch/Fedora) + macOS.
