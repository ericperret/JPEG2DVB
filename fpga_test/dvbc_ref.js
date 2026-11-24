/*
================================================================================
  Nom        : dvbc_ref.js
  Projet     : JPEG2DVB, mode DVB-C (J.83 annexe A, EN 300 429), 16-QAM
  Objet      : référence bit-exacte de dvbc_map (octets → symboles 16-QAM,
               codage différentiel des deux bits de poids fort) et du filtre
               SRRC de roll-off 0,15 (16 coefficients, 64 phases, 1760/27 cycles
               à 80 MHz par symbole) ; vecteurs de test et mesures
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbc_ref.js vect N_OCTETS DOSSIER   (octets.txt, ref_v.txt)
               node dvbc_ref.js mesure                         (MER, crête)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const AL = 0.15, NT = 16, NP = 64, HQ = 14, U = 76, VMAX = 481;
const PAS = 27, PER = 1760;                      // 80 MHz / (13,5 MHz / 11) = 1760 / 27 cycles par symbole

// srrc : E : x (en périodes symbole) → S : réponse en racine de cosinus surélevé (énergie unitaire par T)
function srrc(x) {
    if (Math.abs(x) < 1e-9) { return 1 - AL + 4 * AL / Math.PI; }
    if (Math.abs(Math.abs(x) - 1 / (4 * AL)) < 1e-9) {
        return AL / Math.SQRT2 * ((1 + 2 / Math.PI) * Math.sin(Math.PI / (4 * AL)) + (1 - 2 / Math.PI) * Math.cos(Math.PI / (4 * AL)));
    }
    return (Math.sin(Math.PI * x * (1 - AL)) + 4 * AL * x * Math.cos(Math.PI * x * (1 + AL))) / (Math.PI * x * (1 - (4 * AL * x) ** 2));
}
// coefficients : phase p (milieu de l'intervalle (p + 0,5) / NP), tap t (0 = symbole le plus récent), retard de groupe NT / 2
const HC = Array.from({ length: NP }, (_, p) => Array.from({ length: NT }, (_, t) => Math.round(srrc(t + (p + 0.5) / NP - NT / 2) * (1 << HQ))));

// map : E : octets → S : symboles { I, Q } ∈ {±1, ±3}
//   chaque octet donne deux quadruplets (poids fort d'abord) A B C D ; (A, B) codés en différentiel (EN 300 429 § 4.6) ;
//   le quadrant (I_k Q_k : 00, 10, 11, 01) tourne le point du premier quadrant de 0, π/2, π, 3π/2 (tableau 1)
function map(oct) {
    const I = [], Q = [];
    let ip = 0, qp = 0;
    for (const b of oct) {
        for (const n of [b >> 4, b & 15]) {
            const A = (n >> 3) & 1, B = (n >> 2) & 1, C = (n >> 1) & 1, D = n & 1;
            let ik, qk;
            if ((A ^ B) === 0) { ik = A ^ ip; qk = B ^ qp; } else { ik = A ^ qp; qk = B ^ ip; }
            ip = ik; qp = qk;
            let x = D ? 3 : 1, y = C ? 3 : 1;           // premier quadrant (figure 7) : C D = 00 → (1, 1), 01 → (3, 1), 10 → (1, 3), 11 → (3, 3)
            const r = ik === 0 && qk === 0 ? 0 : ik === 1 && qk === 0 ? 1 : ik === 1 && qk === 1 ? 2 : 3;
            for (let k = 0; k < r; k++) { const t = x; x = -y; y = t; }
            I.push(x); Q.push(y);
        }
    }
    return { I: I, Q: Q };
}
// filtre : E : symboles, n sorties → S : v (I, Q) à 80 MS/s : fenêtre de 16 symboles, phase floor(64 acc / 1760)
function filtre(sy, nout) {
    const vi = new Int32Array(nout), vq = new Int32Array(nout);
    let acc = 0, m = -1;
    for (let o = 0; o < nout; o++) {
        if (acc < PAS) { m++; }
        const p = Math.floor(acc * NP / PER);
        let si = 0, sq = 0;
        for (let t = 0; t < NT; t++) {
            const k = m - t;
            if (k >= 0 && k < sy.I.length) { si += sy.I[k] * U * HC[p][t]; sq += sy.Q[k] * U * HC[p][t]; }
        }
        const rd = v => Math.max(-VMAX, Math.min(VMAX, (v + (1 << (HQ - 1))) >> HQ));
        vi[o] = rd(si); vq[o] = rd(sq);
        acc = (acc + PAS) % PER;
    }
    return { vi: vi, vq: vq };
}
module.exports = { HC, map, filtre, srrc, NT, NP, HQ, U, VMAX, PAS, PER };

if (require.main === module) {
    const arg = process.argv[2];
    if (arg === 'vect') {
        const n = +process.argv[3], dir = process.argv[4];
        let seed = 991;
        const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
        const oct = Uint8Array.from({ length: n }, () => rnd() & 255);
        const sy = map(oct);
        // sorties jusqu'à ce que le dernier symbole soit entré dans la fenêtre (m = nombre de symboles − 1)
        const nsy = sy.I.length;
        const nout = Math.floor((nsy - 1) * PER / PAS) + 1;
        const fl = filtre(sy, nout);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'octets.txt'), Array.from(oct).join('\n') + '\n');
        const o = [];
        for (let i = 0; i < nout; i++) { o.push(fl.vi[i] + ' ' + fl.vq[i]); }
        fs.writeFileSync(path.join(dir, 'ref_v.txt'), o.join('\n') + '\n');
        console.log('écrit : ' + n + ' octets, ' + nsy + ' symboles, ' + nout + ' groupes ; crête ' + Math.max(...Array.from(fl.vi).map(Math.abs)));
    }
    if (arg === 'mesure') {
        let seed = 31337;
        const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
        const oct = Uint8Array.from({ length: 6000 }, () => rnd() & 255);
        const sy = map(oct), nsy = sy.I.length;
        const nout = Math.floor((nsy - 1) * PER / PAS) + 1;
        const fl = filtre(sy, nout);
        let pk = 0, sq = 0;
        for (let i = 0; i < nout; i++) { pk = Math.max(pk, Math.abs(fl.vi[i]), Math.abs(fl.vq[i])); sq += fl.vi[i] ** 2 + fl.vq[i] ** 2; }
        console.log('symboles ' + nsy + ', crête ' + pk + ', sigma par composante ' + Math.sqrt(sq / nout / 2).toFixed(1) + ', coefficients : somme phase 0 ' + HC[0].reduce((a, b) => a + b, 0) + ', crête ' + Math.max(...HC.flat()));
        // invariance différentielle : une rotation de π/2 du flux de symboles ne change que les premiers symboles
    }
}
