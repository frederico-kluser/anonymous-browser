#!/usr/bin/env node
// postinstall — apenas garante execbit dos scripts shell (npm às vezes
// despe mode 755 do tarball). NÃO instala Tor/Camoufox aqui: deferimos pra
// primeira execução de `ghost-browser` (evita sudo prompts em `npm i -g`).

'use strict';

const fs = require('fs');
const path = require('path');

const pkgRoot = path.resolve(__dirname, '..');
const scripts = ['ghost.sh', 'install.sh', 'new-tor-circuit.sh', 'ghost-mail.sh', 'uninstall.sh'];

for (const s of scripts) {
    const p = path.join(pkgRoot, s);
    if (fs.existsSync(p)) {
        try { fs.chmodSync(p, 0o755); } catch (_) { /* ignore */ }
    }
}

console.log('[ghost-browser] instalado. Rode:  ghost-browser');
console.log('[ghost-browser] (primeira execução vai instalar Tor + Camoufox via sudo)');
