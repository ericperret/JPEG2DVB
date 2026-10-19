--==============================================================================
--  Nom        : tb_qpsk.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la mise en correspondance QPSK : entrée = bits
--               codés de l'étape 12, sortie comparée aux symboles entiers I, Q
--               (octets signés) de l'étape 13
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_qpsk is
    generic (
        G_IN    : string  := "conv.bin";
        G_OUT   : string  := "qpsk.bin";
        G_N_SYM : natural := 104448
    );
end entity tb_qpsk;

architecture sim of tb_qpsk is
    signal clk     : std_logic := '0';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : std_logic_vector(1 downto 0) := "00";
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(1 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.qpsk_map port map (s_valid, s_ready, s_data, m_valid, m_ready, m_i, m_q);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
        variable o : std_logic_vector(7 downto 0);
    begin
        wait until rising_edge(clk);
        for k in 0 to G_N_SYM / 4 - 1 loop
            read(f, c);
            o := octet(c);
            for p in 3 downto 0 loop
                s_data  <= o(2 * p + 1 downto 2 * p);
                s_valid <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when s_ready = '1';
                end loop;
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable ci, cq : character;
        variable n, err : natural := 0;
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and n < G_N_SYM then
                read(f, ci); read(f, cq);
                if resize(m_i, 8) /= signed(octet(ci)) or resize(m_q, 8) /= signed(octet(cq)) then
                    if err < 10 then
                        report "ecart au symbole " & integer'image(n) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_SYM then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " symboles identiques";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " symboles differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
