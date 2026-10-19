<!--
  Name     : README.md
  Purpose  : FPGA port of JPEG2DVB (23 cm DVB-S transmitter), VHDL-2008
  Author   : Eric PERRET
  Date     : 2026-10-19
  License  : CC BY-NC 4.0
-->

# JPEG2DVB — FPGA port in VHDL-2008

🇫🇷 [Version française : LISEZMOI.md](LISEZMOI.md)

VHDL modules of the 23 cm DVB-S transmitter (Microchip PolarFire MPF100TC FPGA, specification v0.4). All modules are in one file, `jpeg2dvb_fpga.vhd` (synthesis), and all testbenches in `jpeg2dvb_fpga_tb.vhd` (simulation). Each module reproduces one JPEG2DVB 2.x step **bit for bit**; each GHDL testbench reads the files produced by JPEG2DVB ([`fpga_test/`](../fpga_test/) folder) and compares the module output byte by byte, or sample by sample.

Synthesisable VHDL-2008, `ieee` library only, `valid` / `ready` streaming interfaces (flow control exercised with random gaps in every testbench).

## Modules

| Module | Function | JPEG2DVB step | Testbench | Status |
|---|---|---|---|---|
| `dct8x8_int` | Integer 8 × 8 DCT (2 passes, 8 multipliers per pass) | 02 (integer DCT) | `tb_bloc` | ✔ identical |
| `quant_intra` | Intra quantisation, default matrix, exact division through a reciprocal table; scale code read with each coefficient (one code per row) | 03 | `tb_bloc` | ✔ per-row codes, codes 1 and 31 |
| `rate_ctrl` | TM5 rate control in integers: one quantiser_scale_code per macroblock row, row gate between DCT and quantisation, exact count of the VLC bits, 5-step division | 03 (TM5) | `tb_rc` | ✔ 54 codes, gate checked |
| `zigzag` | Zigzag scan, two ping-pong banks | 04 | `tb_bloc` | ✔ identical |
| `vlc_enc` + `vlc_tab_pkg` | MPEG-2 VLC: differential DC, B.14, escape, end of block | 05 | `tb_vlc` | ✔ bits and lengths |
| `es_mux` + `bit_packer` | Elementary stream: headers, 12-picture GOP, slices with their own scale code, sequence end | 06 | `tb_es` | ✔ 3 pictures |
| `ts_mux` | PES (PTS) and constant-rate transport stream: PAT/PMT 80 ms, PCR 30 ms, null packets | 07, 08 | `tb_octets` | ✔ 976 packets |
| `prbs_disp` | Energy dispersal | 09 | `tb_octets` | ✔ identical |
| `rs_enc` | RS(204,188) | 10 | `tb_octets` | ✔ identical |
| `interleaver` | Forney interleaver I = 12, M = 17 | 11 | `tb_octets` | ✔ identical |
| `conv_enc` | Convolutional encoder K = 7, 171/133, puncturing 1/2 to 7/8 | 12 | `tb_conv` | ✔ all 5 rates |
| `qpsk_map` | QPSK, bit 0 → +1 | 13 | `tb_qpsk` | ✔ identical |
| `srrc_poly` + `srrc_coef_pkg` | SRRC α = 0.35, 8 phases × 13 16-bit coefficients, no multiplier | 14 (`.cs16`) | `tb_srrc` | ✔ 160,000 samples |
| `tx_backend` | Back-end chain: TS → I/Q (steps 09 to 14 assembled) | 08 → 14 | `tb_backend` | ✔ 160,000 samples, one per clock |
| `mire_gen` + `mire_pkg` | Animated 16-colour test pattern, moving square and counter, 4:2:0 macroblocks | 01 (`fpga_test/mire.png`, moving option) | `tb_mire` | ✔ 2 pictures |
| `video_enc` | Front end: test pattern → DCT → TM5 rate control → quantisation → zigzag → VLC → ES → TS | 01 → 08 | `tb_dvbs` | ✔ 791 TS packets |
| `dvbs_tx` | Complete transmitter: test pattern → I/Q (`video_enc` + `tx_backend`) | 01 → 14 | `tb_dvbs` | ✔ 160,000 samples |

Every module passes `ghdl --synth` without latches (synthesisability check; the real synthesis is done in Libero SoC).

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
- DCT: 192 clocks per block (26.7 million coefficients per second at 80 MHz, 15.6 million needed for 720 × 576 at 25 pictures/s).

## To do

1. ✔ Done (2026-10-19): TM5 rate control in integer arithmetic, in JPEG2DVB page 03 (specification item P7), then in VHDL (`rate_ctrl`), bit for bit.
2. Third-order 1-bit sigma-delta modulator, × 8 interpolation, LVDS serialisers (item P3).
3. LSRAM mapping: synchronous read of the interleaver memory (1,122 bytes); pipelining of long paths (quantisation, VLC) after the first Libero synthesis.
4. 720 × 576 mode (doubled test pattern, 45 macroblocks per slice).

Note on the test pattern: for the FPGA 4:2:0 chroma to be exact, colour boundaries of the 16-colour pattern must fall on even coordinates; the chroma of each 2 × 2 block is then the palette value. The moving square and the counter already follow this rule.

## History

| Date | Change |
|---|---|
| 2026-10-19 | Back end (09 to 14) and video side (02 to 08) bit-exact, 19 testbenches; JPEG2DVB page 08 at 2.4 (multiplexer timing in exact integers) |
| 2026-10-19 | Animated test pattern (`mire.js`: PNG for page 01 and `mire_pkg` package), `video_enc` front end and `dvbs_tx` complete transmitter: from the test pattern to I/Q samples, identical to JPEG2DVB; 22 testbenches |
| 2026-10-19 | TM5 rate control (`rate_ctrl`, references regenerated; testbenches to be adapted). Sources merged into `jpeg2dvb_fpga.vhd` and `jpeg2dvb_fpga_tb.vhd`; references, scripts and `run_tests.sh` moved to `fpga_test/` |
| 2026-10-19 | Clean merge (2.0): one header per file, common VHDL-2008 context `jpeg2dvb_ctx`, every function and process commented; `fpga_test/README.md` lists the role of each test file |
| 2026-10-19 | TM5 rate control bit for bit in VHDL: testbenches adapted (per-row codes, per-slice codes, `slice_ok`), new `tb_rc` testbench, `run_tests.sh` 1.2; 23 testbenches OK, 11 modules synthesisable without latches |

## License

CC BY-NC 4.0 — **Eric PERRET**
