/* gen_pkg.js : écrit le texte VHDL du paquetage dvbt_pkg (tables) depuis dvbt_ref.js ; usage : node gen_pkg.js > dvbt_pkg.txt */
'use strict';
const R=require('./dvbt_ref.js');
const w=(a,n)=>{const o=[];for(let i=0;i<a.length;i+=n){o.push('        '+a.slice(i,i+n).join(', '));}return o.join(',\n');};
let t='';
t+=`package dvbt_pkg is
    constant T_AMP  : integer := ${R.AMP};      -- données : I, Q = ±T_AMP
    constant T_PIL  : integer := ${R.AMP_PIL};      -- pilotes : ±T_PIL (4/3)
    constant T_TPS  : integer := ${R.AMP_TPS};      -- pilotes TPS : ±T_TPS
    constant T_VMAX : integer := ${R.VMAX};      -- écrêtage avant le sigma-delta (56 · 481 ≤ 26 966)
    type t_cos_t is array (0 to 512) of integer range -8191 to 8191;
    constant T_COS : t_cos_t := (
${w(Array.from(R.TQ),16)}
    );
    type t_fir_t is array (0 to 34, 0 to 15) of integer range -32768 to 32767;
    constant T_FIR : t_fir_t := (
${R.HI.map((r,p)=>'        '+p+' => ('+r.join(', ')+')').join(',\n')}
    );
    type t_nat_t is array (natural range <>) of natural;
    constant T_CONT : t_nat_t(0 to 44) := (
${w(R.CPIL,15)}
    );
    constant T_TPSC : t_nat_t(0 to 16) := (
${w(R.TPSC,17)}
    );
    function tps_bits return std_logic_vector;   -- 4 trames × 68 bits (trame f, symbole l : indice 68 f + l)
end package dvbt_pkg;

package body dvbt_pkg is
    -- tps_bits : E : — → T : s1 … s53 (synchro, longueur 23, numéro de trame, QPSK, 1/2, garde 1/32, 2K,
    --   le reste à 0), BCH(67, 53) raccourci du polynôme x¹⁴ + x⁹ + x⁸ + x⁶ + x⁵ + x⁴ + x² + x + 1 → S : bits
    function tps_bits return std_logic_vector is
        variable r   : std_logic_vector(0 to 271) := (others => '0');
        variable d   : std_logic_vector(0 to 67);
        variable bch : unsigned(13 downto 0);
        variable din : std_logic_vector(0 to 112);
        variable fb  : std_logic;
        variable sw  : std_logic_vector(0 to 15);
    begin
        for f in 0 to 3 loop
            d := (others => '0');
            if f mod 2 = 0 then sw := "0011010111101110"; else sw := "1100101000010001"; end if;
            d(1 to 16)  := sw;
            d(17 to 22) := "010111";
            d(23 to 24) := std_logic_vector(to_unsigned(f, 2));
            din := (others => '0');
            din(60 to 112) := d(1 to 53);
            bch := (others => '0');
            for i in 0 to 112 loop
                fb  := din(i) xor bch(0);
                bch := shift_right(bch, 1);
                bch(13) := fb;
                if fb = '1' then
                    bch := bch xor to_unsigned(16#1bb0#, 14);
                end if;
            end loop;
            for i in 0 to 13 loop d(54 + i) := bch(i); end loop;
            r(68 * f to 68 * f + 67) := d;
        end loop;
        return r;
    end function;
end package body dvbt_pkg;
`;
process.stdout.write(t);
