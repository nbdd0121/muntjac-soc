set mode [lindex $argv 0]

if { $mode == "nobit" } {
  write_cfgmem -format mcs -size 32 -interface SPIx4 -loaddata {up 0x01000000 firmware.bin } -force -file firmware.mcs
} else {
  write_cfgmem -format mcs -size 32 -interface SPIx4 -loadbit {up 0x00000000 bitstream.bit } -loaddata {up 0x01000000 firmware.bin } -force -file bitstream.mcs
}
