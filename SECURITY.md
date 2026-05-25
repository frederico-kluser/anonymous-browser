# Política de Segurança

## Versões suportadas

| Versão | Suporte                |
| ------ | ---------------------- |
| 0.2.x  | ✅ Bugs e segurança    |
| 0.1.x  | ❌ Sem suporte         |

## Reportar vulnerabilidade

**Não abra issue pública.** Reporte por um destes canais:

1. **GitHub Security Advisories** (preferido):
   <https://github.com/frederico-kluser/anonymous-browser/security/advisories/new>
2. **E-mail**: `security@` no domínio do repositório (ou contato listado no
   perfil do mantenedor).

Inclua na sua mensagem:

- Descrição da vulnerabilidade
- Passos de reprodução (com versão do projeto, OS e versão do Camoufox)
- Impacto estimado
- Versão afetada

Resposta inicial em até 7 dias úteis. O projeto não paga bug bounty
(sem financiamento), mas credita o reporter no advisory público.

## Escopo

**No escopo:**

- Vazamentos de fingerprint NÃO documentados em [`README.md`](README.md)
  na seção "O que ESTE projeto NÃO protege contra".
- Vazamento de IP real (DNS leak, WebRTC leak, conexão direta acidental
  para `clear-net` quando `PROXY=tor`).
- Credenciais (token JWT do `mail.tm`, password persistente) gravadas com
  permissão maior que `600`.
- Persistência indevida de estado entre sessões quando `KEEP` NÃO foi setado
  (perfil descartável deveria ser apagado).
- Comandos sensíveis a injeção em `KEEP`, `PROXY`, `ANON_OS`.

**Fora do escopo:**

- Bugs no Camoufox upstream — reporte em
  <https://github.com/daijro/camoufox>.
- Bugs no Tor — reporte em <https://gitlab.torproject.org/tpo/core/tor/-/issues>.
- Limitações DECLARADAS no README (TLS JA3/JA4 stock, behavioral
  fingerprinting, anti-bot enterprise, mail.tm como confiança no operador,
  etc).
- Ataques que exigem root local na máquina do usuário (modelo de ameaça
  exclui adversário com privilégio igual ou superior ao da sessão).
