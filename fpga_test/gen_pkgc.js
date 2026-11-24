/* gen_pkgc.js : écrit le texte VHDL du paquetage dvbc_pkg (coefficients SRRC 0,15, amplitude) depuis dvbc_ref.js ; usage : node gen_pkgc.js > dvbc_pkg.txt */
'use strict';
const R = require('./dvbc_ref.js');
let t = `package dvbc_pkg is
    constant C_U : integer := ${R.U};            -- DVB-C : amplitude du niveau 1 (symboles ±1, ±3), crête 6,2 · C_U ≤ T_VMAX
    type t_firc_t is array (0 to ${R.NP - 1}, 0 to ${R.NT - 1}) of integer range -32768 to 32767;
    -- SRRC de roll-off 0,15, ${R.NT} coefficients, ${R.NP} phases (milieu de l'intervalle), échelle 2^${R.HQ}, retard de groupe ${R.NT / 2} symboles
    constant T_FIRC : t_firc_t := (
${R.HC.map((r, p) => '        ' + p + ' => (' + r.join(', ') + ')').join(',\n')}
    );
end package dvbc_pkg;
`;
process.stdout.write(t);
