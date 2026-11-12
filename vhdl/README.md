<!--
  Name     : README.md
  Purpose  : FPGA port of JPEG2DVB (23 cm DVB-S transmitter), VHDL-2008
  Author   : Eric PERRET
  Date     : 2026-11-12
  License  : CC BY-NC 4.0
-->

# JPEG2DVB — FPGA port in VHDL-2008

🇫🇷 [Version française : LISEZMOI.md](LISEZMOI.md)

VHDL modules of the 23 cm DVB-S transmitter (Microchip PolarFire MPF050T FPGA, specification v0.4). All modules are in one file, `jpeg2dvb_fpga.vhd` (synthesis), and all testbenches in `jpeg2dvb_fpga_tb.vhd` (simulation). Each module reproduces one JPEG2DVB 2.x step **bit for bit**; each GHDL testbench reads the files produced by JPEG2DVB ([`fpga_test/`](../fpga_test/) folder) and compares the module output byte by byte, or sample by sample.

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
| `csa_enc` + `csa_tab_pkg` | DVB-CSA scrambling of the packets of one PID, fixed key (BISS-1): chained block cipher from the end of the packet, then stream cipher; stand-alone module, not yet in the chain | — (`fpga_test/csa.js`) | `tb_octets` | ✔ 177 packets, boundary cases |
| `prbs_disp` | Energy dispersal | 09 | `tb_octets` | ✔ identical |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identical |
| `interleaver` | Forney interleaver I = 12, M = 17, synchronous-read memory | 11 | `tb_octets` | ✔ identical |
| `conv_enc` | Convolutional encoder K = 7, 171/133, puncturing 1/2 to 7/8 | 12 | `tb_conv` | ✔ all 5 rates |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identical |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0.35, 8 phases × 13 16-bit coefficients, no multiplier | 14 (`.cs16`) | `tb_srrc` | ✔ 160,000 samples |
| `tx_backend` | Back-end chain: TS → I/Q (steps 09 to 14 assembled) | 08 → 14 | `tb_backend` | ✔ 160,000 samples, one per clock |
| `mire_gen` + `mire_pkg` | Animated 16-colour test pattern computed from its geometry (no image memory), moving square and counter, 4:2:0 macroblocks | 01 (`fpga_test/mire.png`, moving option) | `tb_mire` | ✔ 2 pictures |
| `video_enc` | Front end: test pattern → DCT → TM5 rate control → quantisation → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 791 TS packets |
| `dvbs_tx` | Complete transmitter: test pattern → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160,000 samples |
| `bt656_rx` | BT.656 receiver for the TVP5150AM1 decoder: SAV / EAV codes, field, line, Cb Y Cr Y pairs, 27 MHz SCLK clock | PAL input | `tb_bt656` | ✔ 414,720 pairs (4 fields, colour and black and white) |
| `i2c_maitre` + `tvp_ctrl` | TVP5150AM1 control: start-up, identification, forced PAL, VBI off, automatic or forced AIP1A / AIP1B selection, I²C watchdog and bus recovery | PAL input | `tb_tvp` (`tb_tvp5150` model) | ✔ 4 scenarios |
| `dvbs_sd` | Transmitter to the sigma-delta bits; `G_MCPC`: programme 1 camera (`cam_mb` → `codeur`, black picture without a camera), programme 2 test pattern, then `ts_mux` → channel → `sigma_delta` | 01 → 14 | blocks verified by `video`, `mcpc`, `cam`, `chaine`, `sdm` | ✔ composed, end-to-end test pending |
| `codeur` | Complete encoder of one programme: `mire_gen` or `cam_mb` macroblocks → DCT → TM5 rate control → quantisation → zigzag → VLC → ES; 352 × 288 pictures or 720 × 576 as two field pictures (`G_TRAMES`) | 01 → 06 | `tb_codeur` | ✔ compiled, elaborated |
| `cam_mb` | Camera path: BT.656 pairs (27 MHz) → 4:2:0 macroblocks (80 MHz), rounded mean of the chroma lines, crossing between clocks | PAL input | `tb_cam` | ✔ 1,244,160 bytes (`cam_mb.bin`) |
| `horloges` + `sortie_lvds` | Wrappers of the Libero cores: PLLs `PF_CCC_SYS` (80 / 320 MHz) and `PF_CCC_TVP` (14.318182 MHz), LVDS serialiser `PF_IOD_TX_SD` (2 lanes, 640 Mbit/s) | board | `tb_top` (`jpeg2dvb_ip_sim.vhd` models) | to validate in Libero |
| `regs_i2c` + `jpeg2dvb_top` | Top level: PLLs, reset, LVDS, decoder, microcontroller registers, LEDs | board | `tb_top` (`jpeg2dvb_ip_sim.vhd` models) | ✔ registers, LEDs; LVDS reference to regenerate for the MCPC top level |

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

Two programmes in one transport stream (DVB-S, FEC 1/2, 10 MS/s):

| | Programme 1 | Programme 2 |
|---|---|---|
| Source | camera (TVP5150AM1 → `bt656_rx` → `cam_mb`); black picture (Y 16, Cb = Cr = 128, 25 pictures per second) when the camera is absent, back to the camera at the start of a picture | animated test pattern (`mire_gen`), 352 × 288 |
| Encoder | `codeur` 720 × 576: each field (720 × 288, 45 × 18 macroblocks) coded as an MPEG-2 field picture, top then bottom (`G_TRAMES`) | `codeur` 352 × 288 |
| PMT / video PID | 0x0100 / 0x0101 (also carries the PCR) | 0x0200 / 0x0201 |
| Share of the rate | 47 % | 47 % |

The PAT lists both programmes. `ts_mux` (`G_MCPC`, `G_TRAMES1`) schedules the packets by running differences (PAT / PMT, PCR, channel 1, channel 2); a channel-1 picture is made of the two coded fields; PTS = 3,600 · (n + 1) + 9,000 on each channel. The chroma of the camera macroblocks is the rounded mean of the two lines of each pair, (a + b + 1) >> 1. The per-picture budget comes from `budget_image` with 47 % of the rate (50 fields per second on channel 1, 25 pictures per second on channel 2).

Verification: `ts_mux` in MCPC mode is bit-exact against `mcpc.js` (`mcpc` testbench; `ffprobe` sees two programmes, `ffmpeg` decodes both); `cam_mb` is bit-exact against `cam_mb.bin` (`cam` testbench). The composition (`codeur` 720 × 576 in field mode, black picture, MCPC wiring) was only compiled and elaborated: the end-to-end test is the last work item.

## Board top-level entity (`jpeg2dvb_top`)

Clocks: 50 MHz MEMS oscillator (DSC1001) → PLL `PF_CCC_SYS` (80 MHz, 320 MHz for the serialisers) and PLL `PF_CCC_TVP` (exact 14.318182 MHz: VCO 1,575 MHz / 110) to the decoder XTAL1. Reset held until both PLLs are locked. I and Q LVDS outputs at 640 Mbit/s (8:1 serialisers). Active-high LEDs: PLLs locked, decoder present, video locked.

Microcontroller registers (separate I²C bus, FPGA slave at address 2Ah, `regs_i2c`):

| Address | Name | Access | Default | Role |
|---|---|---|---|---|
| 00h | ID | read | 4Ah | FPGA identifier |
| 01h | VERSION | read | 01h | register-map version |
| 02h | MODE | read / write | 00h | standard, FEC, symbol rate |
| 03h | INPUT | read / write | 00h | video source |
| 04h | STATUS | read | — | board status |
| 05h to FFh | — | — | 00h | read as 00h, writes ignored |

MODE (02h):

| Bits | Field | Values |
|---|---|---|
| 7..5 | — | ignored on write, read as 0 |
| 4 | RATE | 0: 10 MS/s; 1: 2.5 MS/s |
| 3..1 | FEC | DVB-S: 000 = 1/2, 001 = 2/3, 010 = 3/4, 011 = 5/6, 100 = 7/8, 101 to 111 reserved; DVB-S2: ignored (QPSK 1/4) |
| 0 | STANDARD | 0: DVB-S; 1: DVB-S2 (QPSK 1/4, normal frames, pilots, CCM) |

| MODE | Standard | FEC | Symbol rate |
|---|---|---|---|
| 00h | DVB-S | 1/2 | 10 MS/s |
| 02h | DVB-S | 2/3 | 10 MS/s |
| 04h | DVB-S | 3/4 | 10 MS/s |
| 06h | DVB-S | 5/6 | 10 MS/s |
| 08h | DVB-S | 7/8 | 10 MS/s |
| 10h | DVB-S | 1/2 | 2.5 MS/s |
| 12h | DVB-S | 2/3 | 2.5 MS/s |
| 14h | DVB-S | 3/4 | 2.5 MS/s |
| 16h | DVB-S | 5/6 | 2.5 MS/s |
| 18h | DVB-S | 7/8 | 2.5 MS/s |
| 01h | DVB-S2 | 1/4 | 10 MS/s |
| 11h | DVB-S2 | 1/4 | 2.5 MS/s |

INPUT (03h):

| Bits | Field | Values |
|---|---|---|
| 7..2 | — | ignored on write, read as 0 |
| 1..0 | SOURCE | 00: automatic (AIP1A, then AIP1B if A is not locked); 01: AIP1A forced; 10: AIP1B forced; 11: test pattern |

STATUS (04h, read only):

| Bit | Field | Values |
|---|---|---|
| 7..4 | — | 0 |
| 3 | INPUT | current decoder input: 0 = AIP1A, 1 = AIP1B |
| 2 | VIDEO | 1: decoder locked on lines and fields |
| 1 | DECODER | 1: TVP5150AM1 identified |
| 0 | PLL | 1: both PLLs locked |

Write: start, 54h, register, data…, stop. Read: start, 54h, register, repeated start, 55h, data… (NACK on the last byte), stop. The pointer advances after each byte. Without a microcontroller the defaults apply. MODE is stored; it will be wired to the chain by the FEC, symbol-rate and DVB-S2 work items. INPUT 3 (test pattern forced on programme 1) is decoded but not yet wired to the chain: programme 1 is the camera, or a black picture when the decoder is not locked.

Single source file: `jpeg2dvb_fpga.vhd` holds every unit, including `horloges` and `sortie_lvds`. The only things created by hand in Libero are the three catalog cores below and the constraints. `jpeg2dvb_ip_sim.vhd` (GHDL models of the three cores) is for simulation only; `jpeg2dvb_top.sdc` holds the constraints of step 7.

### In Libero

1. New project, device MPF050T, package FCG484, VHDL-2008.
2. File ▸ Import ▸ HDL Source Files: `jpeg2dvb_fpga.vhd` only.
3. Catalog (View ▸ Windows ▸ Catalog) ▸ `PF_CCC`, name `PF_CCC_SYS`: input 0 = 50 MHz; feedback Post-VCO, bandwidth High; output 0: enabled, 80 MHz, Global Clock; output 1: enabled, 320 MHz as HS_IO_CLK (option to check in the configurator); PLL lock exposed. Ports: `REF_CLK_0`, `OUT0_FABCLK_0`, `OUT1_HS_IO_CLK_0`, `PLL_LOCK_0`.
4. `PF_CCC`, name `PF_CCC_TVP`: input 0 = 50 MHz; output 0: enabled, 14.318182 MHz (VCO 1,575 MHz / 110), Global Clock; no other output. Ports: `REF_CLK_0`, `OUT0_FABCLK_0`, `PLL_LOCK_0`.
5. `PF_IOD_GENERIC_TX`, name `PF_IOD_TX_SD`: interface TX_DDRX_B_G (the file assumes TX_DDRX_B_G_FA), 8 bits per cycle, 640 Mbps per lane, 2 data lanes, no forwarded clock, LVDS standard (LVDS25 in a 2.5 V bank, LVDS18G in a 1.8 V bank). Ports: `TX_CLK_G`, `HS_IO_CLK`, `ARST_N`, `HS_IO_CLK_PAUSE`, `TX_DATA_0`, `TX_DATA_1`, `TXD`, `TXD_N`.
6. Compare the generated ports (`component/work/<name>/<name>.vhd`) with the component declarations of `horloges` and `sortie_lvds` in `jpeg2dvb_fpga.vhd`; check the TX_DATA bit transmit order in the PF_IOD guide (the file assumes TX_DATA(0) first).
7. Design Hierarchy ▸ `jpeg2dvb_top` ▸ Set As Root. Constraint Manager ▸ Timing, constraints to enter (or import `jpeg2dvb_top.sdc`): `create_clock -name osc_50 -period 20.000 [get_ports osc_50]`, `create_clock -name tvp_sclk -period 37.037 [get_ports tvp_sclk]`, `set_clock_groups -asynchronous -group [get_clocks tvp_sclk]`; then Derive Constraints (PLL clocks 80, 320 and 14.318182 MHz).
8. Pin assignment (I/O Editor) with the PCB: LVDS outputs in a GPIO bank (HSIO banks do not transmit LVDS); `osc_50` and `tvp_sclk` on clock inputs.
9. Synthesize, Place and Route, Verify Timing; the resource report is `synthesis/jpeg2dvb_top.srr`.

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

- Clock: 80 MHz = 8 × symbol rate (10 MS/s). One 1,504-bit TS slot lasts exactly 13,056 clocks.
- The SRRC filter outputs one sample per clock; once the stream is running the back end follows without gaps (1,136 start-up clocks, including the interleaver memory clear).
- DCT: about 140 clocks per block (36.6 million coefficients per second at 80 MHz, 15.6 million needed for 720 × 576 at 25 pictures/s).

## Area (MPF050T target)

Reductions of 2026-11-11, all bit-identical to the references:

| Module | Before | After |
|---|---|---|
| `sdm3`, `sd_entree` | 25-bit comparators, 24-bit registers and candidates | thresholds and corrections are multiples of FS: high-order bits only (15-bit comparators, 14-bit `Pk` and candidates), 17-, 20- and 22-bit states, 16-bit input contributions |
| `quant_intra` | combinational reciprocal table (1,984 × 25 bits), 22 × 24 and 22 × 14 products | synchronous ROM, 17 × 14 and 13 × 13 products |
| `dct8x8_int` | 16 multipliers, 1,664 data flip-flops | 8 multipliers, 414 flip-flops, 64 × 18 and 64 × 12 memories |
| `ts_mux` | four products per slot, 32-bit counters | running differences; no more wrap of the slot counter (8 days) or of the PTS at 2²¹ pictures |
| `interleaver` | asynchronous memory read | synchronous read |
| `mire_gen` | image of 101,376 4-bit words | colour computed by comparisons |

To check in the Libero resource report: `quant_intra` 3 LSRAM (ROM), `interleaver` 1 LSRAM, `dct8x8_int` memories in µSRAM. `quant_intra` assumes |F| ≤ 4,095 (the DCT gives |F| ≤ 2,040).

### Libero synthesis of `jpeg2dvb_top` (2026-11-12)

Synplify Pro, `mpf050tfcvg484-1`, `jpeg2dvb_fpga.vhd` 2.17, run before the three Libero cores were created (`horloges` and `sortie_lvds` as empty boxes) and without clock constraints (100 MHz assumed):

| Resource | Used | Available (MPF050T) |
|---|---|---|
| 4-input LUTs (with the RAM and DSP interface logic) | 30,217 | about 48,000 |
| Registers (with the interface logic) | 11,763 | about 48,000 |
| LSRAM (RAM1K20) | 131 | 160 (81 %) |
| µSRAM (RAM64x12) | 11 | 450 |
| Math blocks (DSP) | 55 | 150 |

Timing estimate before place and route: `clk_sys` 75.0 MHz (13.3 ns) for 80 MHz required (12.5 ns); `tvp_sclk` 129 MHz for 27 MHz. Critical paths: colour computation of `mire_gen` (31 logic levels) and `o_valid` / `m_code` of `vlc_enc`. The place-and-route figures will replace these estimates.

## To do

1. ✔ Done (2026-10-19): TM5 rate control in integer arithmetic, in JPEG2DVB page 03 (specification item P7), then in VHDL (`rate_ctrl`), bit for bit.
2. Sigma-delta output (item P3): ✔ third-order 1-bit modulator and interpolation (`sd_entree`, `sdm3`, `sigma_delta`, `sdm` testbench); ✔ LVDS serialisers (PF_IOD, top level), to be validated in Libero.
3. LSRAM mapping: ✔ synchronous read of the interleaver memory (1,122 bytes) and three-stage quantisation (2026-11-11); measured in Libero on 2026-11-12: 131 of 160 LSRAM; remaining: pipelining of the VLC.
4. 720 × 576 PAL video input: ✔ 3a, TVP5150AM1 control and BT.656 reception (2026-11-04); ✔ 3b (2026-11-11, versions 2.13 to 2.17): `cam_mb` (27 MHz to 80 MHz crossing, 4:2:0 macroblocks), `codeur` 720 × 576 as two field pictures, MCPC (`ts_mux`, `dvbs_sd`), black picture without a camera; compiled and elaborated, end-to-end test pending.
5. DVB-S2 QPSK 1/4, normal frames, pilots, CCM, alongside DVB-S, selected by a DIP switch.
6. ✔ Board top-level entity (2026-11-10); remaining: pin assignment with the PCB, wiring of the MODE register (FEC, symbol rate, DVB-S2 at run time).
7. Video scrambling (BISS-1): ✔ `csa_enc` module (2026-11-11); remaining: insertion between `ts_mux` and energy dispersal, identifier 0000 to 9999 drawn at power-up and the key derived from it, programme 2 in clear (fixed test pattern and identifier).
8. Timing at 80 MHz: pipelining of the colour computation of `mire_gen` and of `vlc_enc` (estimated 75 MHz).
9. Libero: create the three cores, place and route, constraints, pin assignment, resource and timing report (the figures above are before place and route).
10. Final chain test: simulate the camera path from `fpga_test/bt656.bin` (field pictures 720 × 576, MCPC, black picture) and decode the transport stream with a standard decoder (ffmpeg, VLC or the receiver); regenerate the LVDS reference of the `top` testbench (it dates from the single-programme top level).

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

## License

CC BY-NC 4.0 — **Eric PERRET**
