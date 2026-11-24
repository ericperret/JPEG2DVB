/*
================================================================================
  Nom        : gmsk_verif.js
  Projet     : JPEG2DVB, mode GMSK
  Objet      : contrôle de bout en bout du banc tb_gmsk_sd : (1) recalcule le flux de bits
               sigma-delta (voies I et Q) depuis les mots (X, Y) entrés dans gmsk_mod
               (gmsk_ref.js, puis boucle de sdm.js) et le compare octet par octet à la
               sortie de dvbs_sd ; (2) contrôle le flux TS : PAT à un seul programme, PMT
               0x100 seule, aucun PID 0x200 ni 0x201, PCR = 955 + 17 952 par créneau,
               un paquet toutes les 53 191 cycles en régime
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node gmsk_verif.js DOSSIER [INV]   (mots.txt, bits.txt, ts.txt)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const G = require('./gmsk_ref.js');
const FS = 1 << 10, A1 = FS, A2 = 6 * FS, A3 = 16 * FS, GARDE = 1 << 15;
function boucle(u) {
    const v = new Uint8Array(u.length / 8);
    let x1 = 0, x2 = 0, x3 = 0;
    for (let g = 0; g < u.length / 8; g++) {
        const ovf = Math.abs(x1) > GARDE || Math.abs(x2) > GARDE || Math.abs(x3) > GARDE;
        let o = 0;
        for (let r = 0; r < 8; r++) {
            const n = 8 * g + r, s = x3 >= 0 ? 1 : -1;
            o = (o << 1) | (s > 0 ? 1 : 0);
            const n3 = x3 + x2 - A3 * s, n2 = x2 + x1 - A2 * s, n1 = x1 + u[n] - A1 * s;
            x3 = n3; x2 = n2; x1 = n1;
        }
        v[g] = o;
        if (ovf) { x1 = 0; x2 = 0; x3 = 0; }
    }
    return v;
}
const dir = process.argv[2], inv = +(process.argv[3] || 0) === 1;
const lire = f => fs.readFileSync(path.join(dir, f), 'utf8').split('\n').filter(x => x);
let ok = true;

// ---- (1) sigma-delta
const mots = lire('mots.txt').map(Number);
const bits = lire('bits.txt').map(l => l.split(' ').map(Number));
const b = []; for (const w of mots) { b.push((w >> 1) ? 1 : -1, (w & 1) ? 1 : -1); }
const n = Math.min(bits.length, Math.floor((b.length - 1) * G.PER / G.PAS) - 4);
const m = G.modulate(b, n, inv);
const ui = new Float64Array(n * 8), uq = new Float64Array(n * 8);
for (let o = 0; o < n; o++) { for (let r = 0; r < 8; r++) { ui[8 * o + r] = m.vi[o]; uq[8 * o + r] = m.vq[o]; } }
const bi = boucle(ui), bq = boucle(uq);
let err = 0, prem = -1;
for (let k = 0; k < n; k++) { if (bi[k] !== bits[k][0] || bq[k] !== bits[k][1]) { err++; if (prem < 0) { prem = k; } } }
console.log('mots entrés ' + mots.length + ' (' + b.length + ' bits), octets comparés ' + n + ' sur ' + bits.length + ', écarts ' + err + (prem >= 0 ? ' (premier : ' + prem + ')' : ''));
if (err !== 0 || n < 80000) { ok = false; }

// ---- (2) flux TS
const L = lire('ts.txt').map(l => l.split(' ').map(Number));
const pk = []; let cur = null;
for (const [c, s, o] of L) { if (s === 1) { cur = { c: c, b: [] }; pk.push(cur); } if (cur) { cur.b.push(o); } }
const pids = pk.map(p => ((p.b[1] & 31) << 8) | p.b[2]);
const bon = pk.every(p => p.b.length === 188 && p.b[0] === 0x47);
const pat = pk[0];
const patOk = pids[0] === 0 && pat.b[7] === 0x0D && pat.b[13] === 0 && pat.b[14] === 1 && pat.b[15] === 0xE1 && pat.b[16] === 0x00;
const sans2 = !pids.some(p => p === 0x200 || p === 0x201);
let pcrOk = true, nPcr = 0;
pk.forEach((p, k) => {
    const af = (p.b[3] >> 4) & 3;
    if ((af & 2) && (p.b[5] & 16)) {
        const base = p.b[6] * 2 ** 25 + p.b[7] * 2 ** 17 + p.b[8] * 2 ** 9 + p.b[9] * 2 + (p.b[10] >> 7), ext = ((p.b[10] & 1) << 8) | p.b[11];
        // créneau = rang du paquet dans le flux (PAT = 0)
        if (base * 300 + ext !== 955 + 17952 * k) { pcrOk = false; }
        nPcr++;
    }
});
let cadence = true, ref = 0;
{ const k = pk.length - 1; ref = pk[k].c - pk[k - 1].c; if (Math.abs(ref - 53191.1) > 1.5) { cadence = false; } }   // seul le dernier intervalle est en régime
console.log('paquets TS ' + pk.length + ', synchro et longueur ' + (bon ? 'OK' : 'ECHEC') + ', PAT un programme ' + (patOk ? 'OK' : 'ECHEC') + ', aucun PID 0x200/0x201 ' + (sans2 ? 'OK' : 'ECHEC') +
    ', PCR (' + nPcr + ') ' + (pcrOk && nPcr > 0 ? 'OK' : 'ECHEC') + ', intervalle en régime ' + ref + ' cycles ' + (cadence ? 'OK' : 'ECHEC'));
if (!(bon && patOk && sans2 && pcrOk && nPcr > 0 && cadence && pk.length >= 4)) { ok = false; }
console.log(ok ? 'gmsk_sd OK' : 'gmsk_sd ECHEC');
process.exit(ok ? 0 : 1);
