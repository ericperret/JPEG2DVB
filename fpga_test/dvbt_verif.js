/*
================================================================================
  Nom        : dvbt_verif.js
  Projet     : JPEG2DVB, mode DVB-T réduit
  Objet      : contrôle de bout en bout : recalcule le flux de bits sigma-delta
               (voies I et Q) depuis les mots (X, Y) enregistrés par le banc
               tb_dvbt_sd (dvbt_ref.js, puis boucle de sdm.js) et le compare octet
               par octet à la sortie de dvbs_sd
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbt_verif.js DOSSIER   (mots.txt, bits.txt)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const R = require('./dvbt_ref.js');
const FS = 1 << 10, A1 = FS, A2 = 6 * FS, A3 = 16 * FS, GARDE = 1 << 15;
function boucle(u) {
    const v = new Uint8Array(u.length / 8);
    let x1 = 0, x2 = 0, x3 = 0, raz = 0;
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
        if (ovf) { x1 = 0; x2 = 0; x3 = 0; raz++; }
    }
    return v;
}
const dir = process.argv[2];
const mots = Uint8Array.from(fs.readFileSync(path.join(dir, 'mots.txt'), 'utf8').split('\n').filter(x => x).map(Number));
const bits = fs.readFileSync(path.join(dir, 'bits.txt'), 'utf8').split('\n').filter(x => x).map(l => l.split(' ').map(Number));
const nsym = Math.floor(mots.length / R.NPAY), nb = mots.length - mots.length % 126;
const ch = R.chaine(mots.subarray(0, Math.floor(nb / R.NPAY) * R.NPAY), Math.floor(nb / R.NPAY));
const fl = R.filtre(Int32Array.from(ch.flux.re), Int32Array.from(ch.flux.im));
const n = Math.min(bits.length, fl.vr.length);
const ui = new Float64Array(n * 8), uq = new Float64Array(n * 8);
for (let o = 0; o < n; o++) { for (let r = 0; r < 8; r++) { ui[8 * o + r] = fl.vr[o]; uq[8 * o + r] = fl.vi[o]; } }
const bi = boucle(ui), bq = boucle(uq);
let err = 0, prem = -1;
for (let k = 0; k < n; k++) { if (bi[k] !== bits[k][0] || bq[k] !== bits[k][1]) { err++; if (prem < 0) { prem = k; } } }
console.log('mots ' + mots.length + ' (' + nsym + ' symboles), octets comparés ' + n + ' sur ' + bits.length + ', écarts ' + err + (prem >= 0 ? ' (premier : ' + prem + ')' : ''));
console.log(err === 0 && n >= 24640 ? 'dvbt_sd OK' : 'dvbt_sd ECHEC');
process.exit(err === 0 && n >= 24640 ? 0 : 1);
