## Basys 3 Constraints - NES PPU
## Board: Digilent Basys 3 (Artix-7 XC7A35TCPG236-1)

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk_100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100]

## Reset button (center)
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports btnC]

## Switches
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]

## VGA Connector
# Red
set_property -dict { PACKAGE_PIN G19  IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}]
set_property -dict { PACKAGE_PIN H19  IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}]
set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}]
set_property -dict { PACKAGE_PIN N19  IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}]

# Blue
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}]
set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}]
set_property -dict { PACKAGE_PIN K18  IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}]
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}]

# Green
set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}]
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}]
set_property -dict { PACKAGE_PIN G17  IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}]
set_property -dict { PACKAGE_PIN D17  IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}]

# Sync
set_property -dict { PACKAGE_PIN P19  IOSTANDARD LVCMOS33 } [get_ports hsync]
set_property -dict { PACKAGE_PIN R19  IOSTANDARD LVCMOS33 } [get_ports vsync]

## LEDs
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
