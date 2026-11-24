/*
================================================================================
  Nom        : dvbc_mesure.js
  Projet     : JPEG2DVB, mode DVB-C
  Objet      : mesure de bout en bout de dvbc_ref.js : symboles 16-QAM → filtre SRRC 0,15
               → maintien ×8 → sigma-delta 1 bit d'ordre 3 (boucle de sdm.js) → filtre
               adapté à 640 MS/s → MER et taux d'erreur de symbole
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbc_mesure.js [N_SYMBOLES]
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const R = require('./dvbc_ref.js');
const FS = 1 << 10, A1 = FS, A2 = 6 * FS, A3 = 16 * FS, GARDE = 1 << 15;
function boucle(u) {
    const v = new Int8Array(u.length);
    let x1 = 0, x2 = 0, x3 = 0, raz = 0;
    for (let g = 0; g < u.length / 8; g++) {
        const ovf = Math.abs(x1) > GARDE || Math.abs(x2) > GARDE || Math.abs(x3) > GARDE;
        for (let r = 0; r < 8; r++) {
            const n = 8 * g + r, s = x3 >= 0 ? 1 : -1;
            v[n] = s;
            const n3 = x3 + x2 - A3 * s, n2 = x2 + x1 - A2 * s, n1 = x1 + u[n] - A1 * s;
            x3 = n3; x2 = n2; x1 = n1;
        }
        if (ovf) { x1 = 0; x2 = 0; x3 = 0; raz++; }
    }
    return { v: v, raz: raz };
}
const NS = +(process.argv[2] || 3000);
let seed = 2718;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
const oct = Uint8Array.from({ length: NS / 2 }, () => rnd() & 255);
const sy = R.map(oct), nsy = sy.I.length;
const nout = Math.floor((nsy - 1) * R.PER / R.PAS) + 1;
const fl = R.filtre(sy, nout);
const ui = new Float64Array(nout * 8), uq = new Float64Array(nout * 8);
for (let o = 0; o < nout; o++) { for (let r = 0; r < 8; r++) { ui[8 * o + r] = fl.vi[o]; uq[8 * o + r] = fl.vq[o]; } }
const bi = boucle(ui), bq = boucle(uq);
const spc = 8 * R.PER / R.PAS;                      // échantillons à 640 MS/s par symbole
let e = 0, n = 0, bad = 0;
const W = Math.floor(20 * spc);
for (let k = 30; k < nsy - 30; k++) {
    const c = 8 * (k + R.NT / 2) * R.PER / R.PAS;     // centre du symbole k (retard de groupe NT / 2 symboles)
    let si = 0, sq = 0;
    for (let j = -W; j <= W; j++) {
        const o = Math.round(c) + j; if (o < 0 || o >= bi.v.length) { continue; }
        const h = R.srrc((o - c) / spc);
        si += bi.v[o] * h; sq += bq.v[o] * h;
    }
    const ei = si * FS / spc / R.U, eq = sq * FS / spc / R.U;
    e += (ei - sy.I[k]) ** 2 + (eq - sy.Q[k]) ** 2; n++;
    const dec = x => x > 2 ? 3 : x > 0 ? 1 : x > -2 ? -1 : -3;
    if (dec(ei) !== sy.I[k] || dec(eq) !== sy.Q[k]) { bad++; }
}
console.log('symboles mesurés ' + n + ', MER ' + (10 * Math.log10(10 * n / e)).toFixed(1) + ' dB, erreurs de symbole ' + bad + ', remises à zéro sigma-delta ' + bi.raz + '/' + bq.raz);
