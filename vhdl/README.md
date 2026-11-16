<!--
  Name     : README.md
  Purpose  : FPGA port of JPEG2DVB (23 cm DVB-S transmitter), VHDL-2008
  Author   : Eric PERRET
  Date     : 2026-11-16
  License  : CC BY-NC 4.0
-->

# JPEG2DVB — FPGA port in VHDL-2008

🇫🇷 [Version française : LISEZMOI.md](LISEZMOI.md)

VHDL modules of the 23 cm DVB-S / DVB-S2 transmitter (Microchip PolarFire MPF050T or MPF100T FPGA, FCVG484 package, same board; specification v0.4). All modules are in one file, `jpeg2dvb_fpga.vhd` (synthesis), and all testbenches in `jpeg2dvb_fpga_tb.vhd` (simulation). Each module reproduces one JPEG2DVB 2.x step **bit for bit**; each GHDL testbench reads the files produced by JPEG2DVB ([`fpga_test/`](../fpga_test/) folder) and compares the module output byte by byte, or sample by sample.

Synthesisable VHDL-2008, `ieee` library only, `valid` / `ready` streaming interfaces (flow control exercised with random gaps in every testbench).

## Modules

| Module | Function | JPEG2DVB step | Testbench | Status |
|---|---|---|---|---|
| `dct8x8_int` | Integer 8 × 8 DCT: 2 passes, 4 multipliers per pass (coefficient symmetry), row pass while loading, intermediate results and output in memory | 02 (integer DCT) | `tb_bloc` | ✔ identical |
| `quant_intra` | Intra quantisation, default matrix, exact division through reciprocals read from a synchronous ROM (2,048 × 26 bits), three stages; scale code read with each coefficient (one code per row) | 03 | `tb_bloc` | ✔ per-row codes, codes 1 and 31 |
| `rate_ctrl` | TM5 rate control in integers: one quantiser_scale_code per macroblock row, row gate between DCT and quantisation, exact count of the VLC bits, 5-step division | 03 (TM5) | `tb_rc` | ✔ 54 codes, gate checked |
| `zigzag` | Zigzag scan, two ping-pong banks | 04 | `tb_bloc` | ✔ identical |
| `vlc_enc` + `vlc_tab_pkg` | MPEG-2 VLC: differential DC, B.14, escape, end of block | 05 | `tb_vlc` | ✔ bits and lengths |
| `es_mux` + `bit_packer` | Elementary stream: headers, 12-picture GOP, slices with their own scale code, sequence end | 06 | `tb_es` | ✔ 3 pictures |
| `ts_mux` | PES (PTS) and constant-rate transport stream: PAT/PMT 80 ms, PCR 30 ms, null packets; scheduling and PTS by running sums, no multiplier; `G_MCPC` mode: two programmes (PMT 0x0100 / 0x0200), `G_TRAMES1`: channel 1 in field pictures | 07, 08 | `tb_octets` (`G_DUT` 6 = MCPC) | ✔ 976 packets, MCPC 357,200 bytes |
| `csa_enc` + `csa_tab_pkg` | DVB-CSA scrambling of the packets of one PID, fixed key (BISS-1): chained block cipher from the end of the packet, then stream cipher; in the `dvbs_sd` chain between `ts_mux` and energy dispersal (PID 0x0101, active when `biss` = 1) | — (`fpga_test/csa.js`) | `tb_octets` (`csa`, `csa_biss`) | ✔ 177 packets, boundary cases, control word of number 1234 |
| `prbs_disp` | Energy dispersal | 09 | `tb_octets` | ✔ identical |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identical |
| `interleaver` | Forney interleaver I = 12, M = 17, synchronous-read memory | 11 | `tb_octets` | ✔ identical |
| `conv_enc` | Convolutional encoder K = 7, 171/133, puncturing 1/2 to 7/8 | 12 | `tb_conv` | ✔ all 5 rates |
| `dvbs2_tx` + `dvbs2_pkg` + `mem_sdp` | DVB-S2 (EN 302 307-1) QPSK 1/4, 16,200-bit normal frame, pilots, CCM: baseband header, BCH, LDPC (read-modify-write accumulation with forwarding), interleaving, Gold scrambling, physical-layer header | — (`fpga_test/dvbs2.js`, GNU Radio gr-dtv reference) | `tb_s2` | ✔ 3 frames, 99,846 identical symbols |
| `choix_auto` + `tirage_biss` | Automatic mode from the locked inputs, re-evaluated every minute; 4-digit BISS number drawn at power-up | board | `tb_choix`, `tb_biss` | ✔ 4 scenarios and change at the minute; value, hold, BCD |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identical |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0.35, 8 phases × 13 16-bit coefficients, no multiplier | 14 (`.cs16`) | `tb_srrc` | ✔ 160,000 samples |
| `tx_backend` | Back-end chain: TS → I/Q (steps 09 to 14 assembled) | 08 → 14 | `tb_backend` | ✔ 160,000 samples, one per clock |
| `mire_gen` + `mire_pkg` | Animated 16-colour test pattern computed from its geometry (no image memory), moving square and counter, 4:2:0 macroblocks | 01 (`fpga_test/mire.png`, moving option) | `tb_mire` | ✔ 2 pictures |
| `video_enc` | Front end: test pattern → DCT → TM5 rate control → quantisation → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 791 TS packets |
| `dvbs_tx` | Complete transmitter: test pattern → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160,000 samples |
| `bt656_rx` | BT.656 receiver for the TVP5150AM1 decoder: SAV / EAV codes, field, line, Cb Y Cr Y pairs, 27 MHz SCLK clock | PAL input | `tb_bt656` | ✔ 414,720 pairs (4 fields, colour and black and white) |
| `i2c_maitre` + `tvp_ctrl` | TVP5150AM1 control: start-up, identification, forced PAL, VBI off, automatic or forced AIP1A / AIP1B selection, I²C watchdog and bus recovery | PAL input | `tb_tvp` (`tb_tvp5150` model) | ✔ 4 scenarios |
| `dvbs_sd` | Transmitter to the sigma-delta bits; `G_MCPC`: programme 1 camera (`cam_mb` → `codeur`, black picture without camera), programme 2 test pattern (BISS number displayed), `ts_mux` → `csa_enc` → DVB-S (`prbs_disp` … `conv_enc`) or DVB-S2 (`dvbs2_tx`) according to `norme` → `sigma_delta`; reset on standard change | 01 → 14 | blocks checked by `video`, `mcpc`, `cam`, `csa`, `s2`, `chaine`, `sdm` | ✔ assembled, blocks verified; full chain too slow to simulate |
| `codeur` | Complete encoder of one programme: `mire_gen` or `cam_mb` macroblocks → DCT → TM5 rate control → quantisation → zigzag → VLC → ES; 352 × 288 pictures, or 720 × 576 as two field pictures (`G_TRAMES`) | 01 → 06 | `tb_codeur` | ✔ 720 × 576: 4 fields decoded by ffmpeg match the input |
| `cam_mb` | Camera path: BT.656 pairs (27 MHz) → 4:2:0 macroblocks (80 MHz), rounded mean of the chroma lines, crossing between clocks | PAL input | `tb_cam` | ✔ 1,244,160 bytes (`cam_mb.bin`) |
| `horloges` + `sortie_lvds` | Wrappers of the four Libero cores: PLLs `PF_CCC_SYS` (80 MHz) and `PF_CCC_TVP` (14.318 MHz), serialiser clocks `PF_IOD_TX_CCC_IOD` (320 MHz, 80 MHz), LVDS serialiser `PF_IOD_TX_SD` (2 lanes, 640 Mbit/s, I and Q bits interleaved on `TXD_DATA`) | board | `tb_top` (`jpeg2dvb_ip_sim.vhd` models) | ✔ placed and routed in Libero; bit order of each lane to be checked on the board |
| `jpeg2dvb_top` | Top level: PLLs, reset, LVDS, decoder, automatic choice, LEDs | board | `tb_top` (models `jpeg2dvb_ip_sim.vhd`) | ✔ LEDs, decoder absent, 45,247 LVDS groups |

Every module passes `ghdl --synth` without latches (synthesisability check; the real synthesis is done in Libero SoC).

## PAL video input (TVP5150AM1)

Wiring required by `tvp_ctrl`:

- RESETB and PDN driven by the FPGA (`tvp_resetb`, `tvp_pdn`), no RC network: reset must follow the XTAL1 clock, generated by the FPGA PLL (14.31818 MHz);
- SCL and SDA to two FPGA pins (open drain: `scl_oe`, `sda_oe`), 4.7 kΩ pull-ups to 3.3 V;
- YOUT7/I2CSEL: 10 kΩ pull-down (address B8h); INTREQ/GPCL/VBLK: 10 kΩ pull-down;
- SCLK (27 MHz): `bt656_rx` clock; YOUT[7:0]: its `d` input;
- AIP1A and AIP1B: two PAL composite inputs (colour or black and white), the first locked one is used.

`video_ok` flags a decoder locked on lines and fields; otherwise programme 1 sends a black picture (see the MCPC chain below).

## MCPC chain (`dvbs_sd`, `G_MCPC`)

Two programmes in one transport stream (DVB-S, FEC 1/2, 5 MS/s):

| | Programme 1 | Programme 2 |
|---|---|---|
| Source | camera (TVP5150AM1 → `bt656_rx` → `cam_mb`); black picture (Y 16, Cb = Cr = 128, 25 pictures per second) when the camera is absent, back to the camera at the start of a picture | animated test pattern (`mire_gen`), 352 × 288 |
| Encoder | `codeur` 720 × 576: each field (720 × 288, 45 × 18 macroblocks) coded as an MPEG-2 field picture, top then bottom (`G_TRAMES`) | `codeur` 352 × 288 |
| PMT / video PID | 0x0100 / 0x0101 (also carries the PCR) | 0x0200 / 0x0201 |
| Share of the rate | 47 % | 47 % |

The PAT lists both programmes. `ts_mux` (`G_MCPC`, `G_TRAMES1`) schedules the packets by running differences (PAT / PMT, PCR, channel 1, channel 2); a channel-1 picture is made of the two coded fields; PTS = 3,600 · (n + 1) + 9,000 on each channel. The chroma of the camera macroblocks is the rounded mean of the two lines of each pair, (a + b + 1) >> 1. The per-picture budget comes from `budget_image` with 47 % of the rate (50 fields per second on channel 1, 25 pictures per second on channel 2).

Verification: `ts_mux` in MCPC mode is bit-exact against `mcpc.js` (`mcpc` testbench; `ffprobe` sees two programmes, `ffmpeg` decodes both); `cam_mb` is bit-exact against `cam_mb.bin` (`cam` testbench). `codeur` 720 × 576 in field mode: the 4 fields of `cam_mb.bin`, coded then decoded by ffmpeg, match the input. The complete chain is too slow to simulate in GHDL: it is verified block by block, then on the board.

## Board top-level entity (`jpeg2dvb_top`)

Clocks: 50 MHz MEMS oscillator (DSC1001) → PLL `PF_CCC_SYS` (80 MHz) → `PF_IOD_TX_CCC_IOD` (× 4: 320 MHz for the serialisers, and the 80 MHz `TX_CLK_G` that clocks all the logic). Second PLL `PF_CCC_TVP`: 50 MHz → 14.318 MHz to the decoder XTAL1 (14.318182 MHz requested; the configurator accepts three decimals only, 12.7 ppm off). Reset held until the three PLLs are locked. I and Q LVDS outputs at 640 Mbit/s (8:1 serialisers): the bits of both lanes are interleaved on the core's `TXD_DATA` bus (bit k of lane n on `TXD_DATA(2k + n)`, lane I = 0, lane Q = 1).

No microcontroller and no register: fixed settings, 5 MS/s, FEC 1/2. `choix_auto` probes both video inputs (AIP1A then AIP1B, 600 ms each) as soon as the decoder is identified, then every minute; the previous mode is held during the probe:

| Locked inputs | Mode | Programme 1 | Programme 2 |
|---|---|---|---|
| AIP1A only | DVB-S | camera A | test pattern |
| AIP1B only | DVB-S2 QPSK 1/4 | camera B | test pattern |
| A and B | DVB-S, BISS-1 | camera A scrambled | test pattern in clear, number displayed |
| none | DVB-S | black picture | test pattern |

BISS: the 4-digit number (0000 to 9999) is drawn at power-up (`tirage_biss`, counter frozen when the decoder is identified); the session key is this number repeated three times, the control word `S0 S1 S2 (S0+S1+S2) S3 S4 S5 (S3+S4+S5)`. The number is displayed on the programme 2 pattern in BISS mode only. Active-high LEDs: PLLs locked, decoder present, video locked.

### Device, package, voltages

- One board for two devices: MPF050T or MPF100T, **FCVG484** package (484 balls, 0.8 mm pitch, 19 × 19 mm), industrial range (−40 to 100 °C), STD speed. The FCG484 package (1.0 mm pitch) does not exist for the MPF050T: it is dropped.
- Every I/O is at 3.3 V: LVCMOS33 for the signals, LVDS33 for the I/Q outputs. Banks 2 and 4 (GPIO) at 3.3 V; banks 0 and 1 (HSIO, 1.8 V at most) and the transceivers are unused.
- FPGA rails: VDD 1.0 V, VDD18 1.8 V, VDD25 2.5 V; VDDI2, VDDI4, VDDAUX2, VDDAUX4 and VDDI3 (JTAG) at 3.3 V; the rails of unused banks and functions (VDDI0, VDDI1, VDDA, VDDA25, VDD_XCVR_CLK, XCVR_VREF) go to ground through 10 kΩ.

### Pin assignment (`jpeg2dvb_top.pdc` 1.0)

Arranged by quadrant, package seen from above, ball A1 top left. Board layout: video on the left, FPGA in the centre, I/Q and RF chain on the right, supplies at the top, LEDs and programming at the bottom.

| Function | Balls | Bank | Standard |
|---|---|---|---|
| `osc_50` | A10 | 2 | LVCMOS33 |
| `tvp_sclk` | G4 | 4 | LVCMOS33 |
| `tvp_d[0]` to `tvp_d[7]` | H2, J2, J1, J4, K1, L1, L2, M4 | 4 | LVCMOS33 |
| `tvp_xtal1`, `tvp_resetb`, `tvp_pdn` | F3, E3, F5 | 4 | LVCMOS33 |
| `tvp_scl`, `tvp_sda` | G3, G2 | 4 | LVCMOS33 |
| `led_pll`, `led_tvp`, `led_video` | R3, R4, T1 | 4 | LVCMOS33 |
| `sd_i_p` / `sd_i_n` | B19 / B20 | 2 | LVDS33 |
| `sd_q_p` / `sd_q_n` | A20 / A21 | 2 | LVDS33 |

Deviations imposed by the package: only the top and left-side balls accept 3.3 V; the I/Q outputs are therefore top right, the LEDs at the bottom of the left side, and JTAG stays on its fixed balls (F6 to H10). Libero accepts this pin assignment without error or warning on both devices.

The schematic of what enters and leaves the FPGA (azs-cad format) is in [`carte/`](../carte/), with the table of the 484 balls.

### Unattended Libero flow (`jpeg2dvb_libero.tcl` 1.2)

The `vhdl/` folder is the batch: `jpeg2dvb_libero.tcl`, `jpeg2dvb_fpga.vhd` (single source file, including `horloges` and `sortie_lvds`), `jpeg2dvb_top.sdc`, `jpeg2dvb_top.pdc`, `sonde.vhd` and `coeurs/` (the four cores exported as Tcl). The script (Libero SoC 2026.1, script mode, Libero window closed) writes every setting, with no default setting:

1. cores: `coeurs/*.tcl`; if missing, they are exported from a reference project (`REF` variable of the script);
2. package pin table, obtained from Libero with the `sonde.vhd` design;
3. pin assignment: `jpeg2dvb_top.pdc` of the batch, otherwise a computed assignment;
4. for the MPF050T then the MPF100T: new project, VHDL-2008, block mode off, cores, constraints (`jpeg2dvb_top.sdc` and PLL clocks through `derive_constraints_sdc`), synthesis, place and route, timing;
5. `resultats/bilan.txt`, `resultats/journal.txt` and the `jpeg2dvb_resultats.tgz` archive.

Launch, in the batch folder, once and in the foreground (two simultaneous runs in the same folder destroy each other):

```
libero SCRIPT:jpeg2dvb_libero.tcl LOGFILE:jpeg2dvb_libero.log
```

About 20 minutes per device on a PC with 4 GB of memory; script mode is about ten times faster than the graphical interface.

The four cores:

| Core | Catalog | Settings |
|---|---|---|
| `PF_CCC_SYS` | `PF_CCC` | 50 MHz → 80 MHz, Post-VCO feedback |
| `PF_CCC_TVP` | `PF_CCC` | 50 MHz → 14.318 MHz |
| `PF_IOD_TX_CCC_IOD` | `PF_IOD_TX_CCC` | 80 MHz reference, × 4, 640 Mbit/s, ratio 8, clock alignment exposed |
| `PF_IOD_TX_SD` | `PF_IOD_GENERIC_TX` | `TX_DDRX_B`, 640 Mbit/s, 8 bits per cycle, 2 differential lanes, no forwarded clock |

Pitfalls met:

- the core catalog must be downloaded (Libero default repositories) before any core is created;
- "Enable block creation" (Project Settings, Design flow) must be unchecked, otherwise synthesis inserts no I/O buffers;
- the outputs of a `PF_IOD_GENERIC_TX` serialiser must be placed and locked before place and route;
- at 640 Mbit/s this serialiser requires the `PF_IOD_TX_CCC` clock core, whose reference is 320 MHz divided by an integer (80 MHz here): a 50 MHz oscillator cannot feed it directly;
- without clock constraints the timing report shows "N/A" and "no violation" proves nothing.

`jpeg2dvb_ip_sim.vhd` 2.2 (GHDL models of the four cores) is for simulation only.

## Running the tests

```
sudo apt-get install ghdl        # GHDL 4.x
cd fpga_test
./run_tests.sh                   # all testbenches + synthesis check
./run_tests.sh conv              # testbenches whose name contains "conv"
```

Each line prints `OK …` (output identical to JPEG2DVB) or `ECHEC …` (first mismatches reported).

## References

`fpga_test/` holds the test tools (`run_tests.sh`, Node scripts) and excerpts of JPEG2DVB 2.x outputs:

- back end: 64 TS packets of a one-second stream (photo, 25 pictures, FEC 1/2, α = 0.35) and their outputs at steps 09 to 14; `node refs.js FOLDER` extracts them and rewrites the `srrc_coef_pkg` package in `jpeg2dvb_fpga.vhd`; the 2/3 to 7/8 references come from page 12 set to those rates;
- video: 3 pictures of `dur.png`, integer DCT, TM5 rate control; `node refs_video.js FOLDER`; codes 1 and 31 come from page 03;
- `node gen_vlc.js` regenerates the VLC tables from page 05.

## Throughput

- Clock: 80 MHz = 16 × symbol rate (5 MS/s; 8 × at 10 MS/s in the benches). One 1,504-bit TS slot lasts 26,112 clocks at 5 MS/s (13,056 at 10 MS/s).
- The SRRC filter outputs one sample per clock; once the stream is running the back end follows without gaps (1,136 start-up clocks, including the interleaver memory clear).
- DCT: about 140 clocks per block (36.6 million coefficients per second at 80 MHz, 15.6 million needed for 720 × 576 at 25 pictures/s).

## Area and timing

Reductions of 2026-11-11, all bit-identical to the references:

| Module | Before | After |
|---|---|---|
| `sdm3`, `sd_entree` | 25-bit comparators, 24-bit registers and candidates | thresholds and corrections are multiples of FS: high-order bits only (15-bit comparators, 14-bit `Pk` and candidates), 17-, 20- and 22-bit states, 16-bit input contributions |
| `quant_intra` | combinational reciprocal table (1,984 × 25 bits), 22 × 24 and 22 × 14 products | synchronous ROM, 17 × 14 and 13 × 13 products |
| `dct8x8_int` | 16 multipliers, 1,664 data flip-flops | 8 multipliers, 414 flip-flops, 64 × 18 and 64 × 12 memories |
| `ts_mux` | four products per slot, 32-bit counters | running differences; no more wrap of the slot counter (8 days) or of the PTS at 2²¹ pictures |
| `interleaver` | asynchronous memory read | synchronous read |
| `mire_gen` | image of 101,376 4-bit words | colour computed by comparisons |

In the Libero resource report: `quant_intra` 3 LSRAM (ROM), `interleaver` 1 LSRAM, `dct8x8_int` memories in µSRAM. `quant_intra` assumes |F| ≤ 4,095 (the DCT gives |F| ≤ 2,040).

### Place and route of `jpeg2dvb_top` (2026-11-16)

Libero SoC 2026.1, `jpeg2dvb_fpga.vhd` 2.26, pin assignment `jpeg2dvb_top.pdc` 1.0, FCVG484 package, industrial range, STD speed; timing analysed on every corner:

| | MPF050T | MPF100T |
|---|---|---|
| 4-input LUTs | 35,287 / 48,144 (73 %) | 35,287 / 108,600 (32 %) |
| Registers | 13,859 (29 %) | 13,859 (13 %) |
| LSRAM | 143 / 160 (89 %) | 143 / 352 (41 %) |
| µSRAM | 13 / 450 | 13 / 1,008 |
| Math blocks | 56 / 150 (37 %) | 56 / 336 (17 %) |
| PLLs | 3 / 8 | 3 / 8 |
| Slack at 80 MHz, worst case | +0.507 ns | +0.346 ns |
| Hold slack, worst case | +0.072 ns | +0.067 ns |
| Violations | none | none |

**The MPF050T is feasible**, with the same pin assignment as the MPF100T (identical pin files). Two reservations: the MPF050T is almost full in memory (17 LSRAM blocks free), and the timing slack is thin on both devices: it is checked again at every VHDL version. Full figures: `resultats/bilan.txt` and `resultats/journal.txt`.

The first synthesis (2026-11-12, version 2.17, before the cores and without clock constraints) gave 30,217 LUTs, 131 LSRAM, 55 math blocks and an estimated 75 MHz; `mire_gen` and `vlc_enc` have been pipelined since (2.19).

## To do

1. ✔ Complete chain of the .vhd (versions 2.19 to 2.27): DVB-S, DVB-S2, BISS, automatic choice, MCPC, camera; full test suite and GHDL synthesis OK on 2.24; versions 2.25 to 2.27 only touch `horloges`, `sortie_lvds`, `jpeg2dvb_top` and comments.
2. ✔ Libero (2026-11-16): four cores, script-mode flow, place and route and timing at 80 MHz on the MPF050T and the MPF100T, no violation.
3. ✔ Pin assignment by quadrant (`jpeg2dvb_top.pdc` 1.0) and schematic of the FPGA inputs and outputs ([`carte/`](../carte/)).
4. Video input delays: the arrival time of `tvp_d[7:0]` relative to `tvp_sclk` (27 MHz) is not declared in `jpeg2dvb_top.sdc`; to be added from the TVP5150AM1 data sheet, then rerun the Libero flow.
5. Bit order inside each LVDS lane (bit 0 sent first): assumption to be checked on the board.
6. Simulation of the complete chain (camera, MCPC, DVB-S2) is too slow in GHDL: verified block by block; to be checked on the board. LVDS reference of the `top` bench to be regenerated for the MCPC top level.
7. Board: supplies, RF stage, printed circuit; no test on a board so far. Final test: read the Transport Stream with a standard decoder (DVB-S, DVB-S2, BISS).

Note on the test pattern: for the FPGA 4:2:0 chroma to be exact, colour boundaries of the 16-colour pattern must fall on even coordinates; the chroma of each 2 × 2 block is then the palette value. The moving square and the counter already follow this rule.

## History

| Date | Change |
|---|---|
| 2026-10-19 | Back end (09 to 14) and video side (02 to 08) bit-exact, 19 testbenches; JPEG2DVB page 08 at 2.4 (multiplexer timing in exact integers) |
| 2026-10-19 | Animated test pattern (`mire.js`: PNG for page 01 and `mire_pkg` package), `video_enc` front end and `dvbs_tx` complete transmitter: from the test pattern to I/Q samples, identical to JPEG2DVB; 22 testbenches |
| 2026-10-19 | TM5 rate control (`rate_ctrl`, references regenerated; testbenches to be adapted). Sources merged into `jpeg2dvb_fpga.vhd` and `jpeg2dvb_fpga_tb.vhd`; references, scripts and `run_tests.sh` moved to `fpga_test/` |
| 2026-10-19 | Clean merge (2.0): one header per file, common VHDL-2008 context `jpeg2dvb_ctx`, every function and process commented; `fpga_test/README.md` lists the role of each test file |
| 2026-10-19 | TM5 rate control bit for bit in VHDL: testbenches adapted (per-row codes, per-slice codes, `slice_ok`), new `tb_rc` testbench, `run_tests.sh` 1.2; 23 testbenches OK, 11 modules synthesisable without latches |
| 2026-11-04 | PAL video input, work item 3a: `bt656_rx`, `i2c_maitre`, `tvp_ctrl` (TVP5150AM1 without a microcontroller); `bt656.js`, `tb_bt656` and `tb_tvp` testbenches (`tb_tvp5150` I²C model, standard-mode timing); `run_tests.sh` 1.5; 28 testbenches OK, 16 modules synthesisable without latches |
| 2026-11-10 | Libero: explicit `library` / `use` clauses instead of the VHDL-2008 `context`, interleaver pointers without initial value (Synplify MF682); first error-free synthesis of `dvbs_tx`. Top level (work item 6): `jpeg2dvb_top`, `dvbs_sd`, `regs_i2c` (I²C slave 2Ah), forced input in `tvp_ctrl`, `jpeg2dvb_ip_libero.vhd` / `jpeg2dvb_ip_sim.vhd`, `jpeg2dvb_top.sdc`; `tvp_force` and `top` testbenches; `run_tests.sh` 1.6 |
| 2026-11-11 | Area reduction for the MPF050T, output bit-identical (`jpeg2dvb_fpga.vhd` 2.6 to 2.11): `sdm3` and `sd_entree` on the useful bits, `quant_intra` with a synchronous ROM, `dct8x8_int` with 4 multipliers per pass and memories, `ts_mux` without multipliers, `interleaver` with synchronous read, computed test pattern (`mire.js` 1.2, `fusion.js` 1.1) |
| 2026-11-11 | Fixed-key DVB-CSA scrambling (BISS-1): `csa_enc`, `csa_tab_pkg`, `csa.js` reference (self-test on two public vectors), `csa` testbench; `jpeg2dvb_fpga.vhd` 2.12, `jpeg2dvb_fpga_tb.vhd` 2.7, `run_tests.sh` 1.7 |
| 2026-11-11 | MCPC and camera chain (`jpeg2dvb_fpga.vhd` 2.13 to 2.17): `ts_mux` with two programmes (`mcpc.js`, `mcpc` testbench), `cam_mb` (`bt656.js` 1.1 writes `cam_mb.bin`, `cam` testbench), `codeur` 720 × 576 in field pictures (`tb_codeur`), `dvbs_sd` and `jpeg2dvb_top` in MCPC (camera on programme 1, test pattern on programme 2, 47 % of the rate each), black picture without a camera; `run_tests.sh` 1.9 |
| 2026-11-12 | First Libero synthesis of `jpeg2dvb_top` on the MPF050T (131 of 160 LSRAM, 55 of 150 DSP, 75 MHz estimated for 80 MHz required). `jpeg2dvb_fpga.vhd` 2.18: `horloges` and `sortie_lvds` inside the single file, `jpeg2dvb_ip_libero.vhd` removed, `jpeg2dvb_ip_sim.vhd` 2.0 (models of the three Libero cores); documentation brought up to date |
| 2026-11-12 | Fixed settings (5 MS/s, FEC 1/2) and automatic choice (`choix_auto`), `regs_i2c` removed (2.20); DVB-S2 QPSK 1/4 (`dvbs2_tx`, 2.21); BISS-1 in the chain, `tirage_biss`, number on the test pattern (2.22); three `dvbs2_tx` fixes (`tb_s2` identical to `dvbs2.js`, 2.23); 720 × 576 `codeur`: `vlc_enc` received 22 columns instead of 45, camera picture fixed (2.24); timing: `mire_gen` and `vlc_enc` pipelined (2.19); MPF100T target; `run_tests.sh` 2.0 |
| 2026-11-13 | Libero cores as generated (2.25): `PF_CCC_SYS` (80 MHz) feeds `PF_IOD_TX_CCC_IOD` (320 MHz, 80 MHz, clock alignment), 16-bit `TXD_DATA` bus; I and Q lane bits interleaved on `TXD_DATA` (2.26); `jpeg2dvb_ip_sim.vhd` 2.2 (four cores) |
| 2026-11-16 | Script-mode Libero flow (`jpeg2dvb_libero.tcl` 1.2, `sonde.vhd`, `coeurs/`), `jpeg2dvb_top.sdc` 1.1, pin assignment by quadrant `jpeg2dvb_top.pdc` 1.0; FCVG484 package, everything at 3.3 V (LVCMOS33, LVDS33); place and route and timing without violation on the MPF050T and the MPF100T with the same pin assignment; schematic of the FPGA inputs and outputs in `carte/`; `jpeg2dvb_fpga.vhd` 2.27 (comments only); `jpeg2dvb_ip_libero.vhd` removed; documentation brought up to date |

## License

CC BY-NC 4.0 — **Eric PERRET**
