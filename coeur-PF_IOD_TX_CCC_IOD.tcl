# Exporting Component Description of PF_IOD_TX_CCC_IOD to TCL
# Family: PolarFire
# Part Number: MPF100T-FCG484E
# Create and Configure the core component PF_IOD_TX_CCC_IOD
create_and_configure_core -core_vlnv {Actel:SystemBuilder:PF_IOD_TX_CCC:1.0.131} -component_name {PF_IOD_TX_CCC_IOD} -params {\
"BCLKSCLK_TRN_DIR:BACKWARD" \
"BCLK_OFFSET:3" \
"CCC_PLL_MULTIPLIER:4" \
"CCC_PLL_REF_FREQ:80.000" \
"DATA_RATE:640" \
"DATA_RATIO:8" \
"EXPOSE_BCLK_OFFSET:false" \
"EXPOSE_CLK_ALIGN_IOD_RX:true" \
"EXPOSE_EXTRA_TRAINING_PORTS:false" \
"PLL_ENABLE_DRI_IF:false" \
"PLL_ENABLE_OUTPUT_2:false" \
"PLL_ENABLE_OUTPUT_3:false" \
"PLL_OUTPUT_DIVIDER_2:4" \
"PLL_OUTPUT_DIVIDER_3:4" \
"PLL_OUTPUT_FREQ_2:80.000 MHz" \
"PLL_OUTPUT_FREQ_3:80.000 MHz" \
"PLL_OUT_2_TO_CLKINT:true" \
"PLL_OUT_2_TO_DEDICATED:false" \
"PLL_OUT_2_TO_GCLKINT:false" \
"PLL_OUT_3_TO_CLKINT:true" \
"PLL_OUT_3_TO_DEDICATED:false" \
"PLL_OUT_3_TO_GCLKINT:false" \
"RATIO:4" \
"RX_FRAC_MODE:false" \
"TX_CLK_TO_DATA:ALIGNED" }
# Exporting Component Description of PF_IOD_TX_CCC_IOD to TCL done
