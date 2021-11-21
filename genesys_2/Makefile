default: firmware.mcs

.PHONY: default firmware.elf

device_tree.dts:
	cp data/device_tree.dts .

firmware.elf: device_tree.dts
	cd ../firmware; DTS=$(realpath device_tree.dts) cargo build --release
	cp ../firmware/target/riscv64imac-unknown-none-elf/release/bootloader $@

firmware.bin: firmware.elf
	riscv64-unknown-elf-objcopy $< $@ -O binary

firmware.mcs: firmware.bin
	vivado -mode batch -source util/generate_mcs.tcl
