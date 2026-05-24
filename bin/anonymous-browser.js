#!/usr/bin/env node
// anonymous-browser — launcher Node instalado por `npm i -g anonymous-browser`.
// Pergunta sobre e-mail descartável, garante deps (Tor + venv Camoufox) na
// primeira execução, e dispara anonymous.sh.

'use strict';

const { spawnSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const readline = require('readline');

const pkgRoot = path.resolve(__dirname, '..');
const anonScript = path.join(pkgRoot, 'anonymous.sh');
const installSh = path.join(pkgRoot, 'install.sh');
const venv = path.join(os.homedir(), '.camoufox-venv');

// npm às vezes preserva mode 644 do tarball. chmod best-effort para os .sh.
for (const s of ['anonymous.sh', 'install.sh', 'new-tor-circuit.sh', 'anonymous-mail.sh']) {
    const p = path.join(pkgRoot, s);
    try { fs.chmodSync(p, 0o755); } catch (_) { /* ignore */ }
}

if (!fs.existsSync(anonScript)) {
    console.error(`[anonymous-browser] não achei anonymous.sh em ${pkgRoot}`);
    console.error('                reinstale com:  npm i -g anonymous-browser');
    process.exit(1);
}

// Primeira execução: roda install.sh do próprio pacote.
// ANON_SKIP_WRAPPER=1 impede install.sh de criar wrapper em ~/.local/bin,
// já que o npm criou um em /usr/local/bin (ou similar) ao instalar este pacote.
if (!fs.existsSync(venv)) {
    console.log('[anonymous-browser] primeira execução — instalando dependências (Tor + Camoufox)...');
    const r = spawnSync('bash', [installSh], {
        stdio: 'inherit',
        env: Object.assign({}, process.env, { ANON_SKIP_WRAPPER: '1' }),
    });
    if (r.status !== 0) {
        console.error('[anonymous-browser] install.sh falhou — veja erros acima.');
        process.exit(r.status || 1);
    }
}

async function ask(question) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        rl.question(question, (answer) => { rl.close(); resolve(answer); });
    });
}

(async () => {
    // Só pergunta se MAIL não veio do ambiente — assim scripts podem fixar MAIL=0/1.
    if (!('MAIL' in process.env) || process.env.MAIL === '') {
        if (process.stdin.isTTY && process.stdout.isTTY) {
            const ans = await ask('[anonymous-browser] Quer e-mail temporário descartável? [y/N] ');
            const low = String(ans || '').trim().toLowerCase();
            process.env.MAIL = /^(y|yes|s|sim)$/.test(low) ? '1' : '0';
        } else {
            process.env.MAIL = '0';
        }
    }

    const child = spawn('bash', [anonScript, ...process.argv.slice(2)], {
        stdio: 'inherit',
        env: process.env,
    });
    child.on('exit', (code, signal) => {
        if (signal) { process.kill(process.pid, signal); return; }
        process.exit(code == null ? 0 : code);
    });
    child.on('error', (err) => {
        console.error(`[anonymous-browser] falha ao executar anonymous.sh: ${err.message}`);
        process.exit(1);
    });
})();
