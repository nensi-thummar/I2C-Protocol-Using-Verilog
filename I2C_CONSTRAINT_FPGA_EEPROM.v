# ============================================================
# constraints.xdc — Arty A7-100T
# ============================================================

# Clock
set_property PACKAGE_PIN E3        [get_ports clk]
set_property IOSTANDARD  LVCMOS33  [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Buttons
set_property PACKAGE_PIN D9        [get_ports btn0]
set_property IOSTANDARD  LVCMOS33  [get_ports btn0]
set_property PACKAGE_PIN C9        [get_ports btn1]
set_property IOSTANDARD  LVCMOS33  [get_ports btn1]

# PMOD JA — SDA and SCL with internal pull-ups
set_property PACKAGE_PIN G13       [get_ports ja0]
set_property IOSTANDARD  LVCMOS33  [get_ports ja0]
set_property PULLUP      true      [get_ports ja0]

set_property PACKAGE_PIN B11       [get_ports ja1]
set_property IOSTANDARD  LVCMOS33  [get_ports ja1]
set_property PULLUP      true      [get_ports ja1]

# Plain LEDs LD0–LD3
set_property PACKAGE_PIN H5        [get_ports {led[0]}]
set_property PACKAGE_PIN J5        [get_ports {led[1]}]
set_property PACKAGE_PIN T9        [get_ports {led[2]}]
set_property PACKAGE_PIN T10       [get_ports {led[3]}]
set_property IOSTANDARD  LVCMOS33  [get_ports {led[*]}]

# RGB LEDs — Red channel only
set_property PACKAGE_PIN G6        [get_ports {led_r[0]}]
set_property PACKAGE_PIN F6        [get_ports {led_r[1]}]
set_property PACKAGE_PIN E1        [get_ports {led_r[2]}]
set_property PACKAGE_PIN F1        [get_ports {led_r[3]}]
set_property IOSTANDARD  LVCMOS33  [get_ports {led_r[*]}]



