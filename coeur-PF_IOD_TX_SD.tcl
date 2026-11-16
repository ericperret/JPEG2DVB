# Exporting Component Description of PF_IOD_TX_SD to TCL
# Family: PolarFire
# Part Number: MPF100T-FCG484E
# Create and Configure the core component PF_IOD_TX_SD
create_and_configure_core -core_vlnv {Actel:SystemBuilder:PF_IOD_GENERIC_TX:2.0.117} -component_name {PF_IOD_TX_SD} -params {\
"CLK_ALIGN_IOD_RX_WIDTH:3" \
"DATA_RATE:640" \
"DATA_RATIO:8" \
"DATA_WIDTH:7" \
"DDR_MODE:DDR" \
"DISABLE_CLK_TRAINING:false" \
"ENABLE_CLK_PATTERN_USER_CTRL:false" \
"EXPOSE_DYNAMIC_DELAY_CTRL:false" \
"IO_NUMBER:2" \
"NEED_CLK_TRAINING:true" \
"NEED_LANECTRL:false" \
"NEED_TIP:false" \
"OE_WIDTH:9" \
"RATIO:4" \
"SIMULATION_MODE:FULL" \
"TXCTL_SPLIT_WIDTH:1" \
"TXD_SPLIT_WIDTH:2" \
"TX_CLK_DIFFERENTIAL:false" \
"TX_CLK_SOURCE:HS_IO_CLK" \
"TX_CLK_TO_DATA:NO_FWD_CLOCK" \
"TX_DATA_BUS_MODE:TX_DATA_SPREAD" \
"TX_DATA_DIFFERENTIAL:true" \
"TX_ENABLED:true" \
"TX_INTERFACE_NAME:TX_DDRX_B" \
"TX_IOG_ARCHETYPE:TX_DDRX_B_X4" \
"TX_MIPI_MODE:false" \
"TX_OE_CONTROL:DISABLED" }
# Exporting Component Description of PF_IOD_TX_SD to TCL done
