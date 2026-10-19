--==============================================================================
--  Nom        : tx_backend.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : chaîne arrière DVB-S complète, du Transport Stream aux
--               échantillons I/Q mis en forme : dispersion d'énergie →
--               RS(204,188) → entrelaceur → codeur convolutif → QPSK → SRRC ;
--               référence bit à bit : JPEG2DVB, étape 08 en entrée, fichier
--               .cs16 de l'étape 14 en sortie
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : paquets TS de 188 octets (s_sop sur la synchro 0x47) ;
--               sortie : I, Q signés 16 bits, 8 échantillons par symbole
--  Débit      : horloge = 8 × débit symbole (80 MHz pour 10 MS/s) ; le SRRC
--               impose le rythme, le contrôle de flux remonte jusqu'à l'entrée TS
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity tx_backend is
    generic (
        G_FEC : natural range 0 to 4 := 0           -- 0 = 1/2 … 4 = 7/8
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity tx_backend;

architecture rtl of tx_backend is
    signal p_valid, p_ready, p_sop : std_logic;
    signal p_data                  : octet_t;
    signal r_valid, r_ready, r_sop : std_logic;
    signal r_data                  : octet_t;
    signal e_valid, e_ready, e_sop : std_logic;
    signal e_data                  : octet_t;
    signal c_valid, c_ready        : std_logic;
    signal c_data                  : std_logic_vector(1 downto 0);
    signal q_valid, q_ready        : std_logic;
    signal q_i, q_q                : signed(1 downto 0);
begin
    u_prbs : entity work.prbs_disp
        port map (clk, rst, s_valid, s_ready, s_data, s_sop, p_valid, p_ready, p_data, p_sop);
    u_rs : entity work.rs_enc
        port map (clk, rst, p_valid, p_ready, p_data, p_sop, r_valid, r_ready, r_data, r_sop);
    u_inter : entity work.interleaver
        port map (clk, rst, r_valid, r_ready, r_data, r_sop, e_valid, e_ready, e_data, e_sop);
    u_conv : entity work.conv_enc generic map (G_FEC => G_FEC)
        port map (clk, rst, e_valid, e_ready, e_data, c_valid, c_ready, c_data);
    u_qpsk : entity work.qpsk_map
        port map (c_valid, c_ready, c_data, q_valid, q_ready, q_i, q_q);
    u_srrc : entity work.srrc_poly
        port map (clk, rst, q_valid, q_ready, q_i, q_q, m_valid, m_ready, m_i, m_q);
end architecture rtl;
