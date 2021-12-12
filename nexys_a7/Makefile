default: firmware

.PHONY: default firmware

CARGO_OUT_DIR=$(realpath .)/target/riscv64imac-unknown-none-elf/release

device_tree.dts:
	cp data/device_tree.dts .

# Files colleted by Cargo
-include $(CARGO_OUT_DIR)/bootloader.d

$(CARGO_OUT_DIR)/bootloader: device_tree.dts
	cd ../firmware; CARGO_TARGET_DIR=$(abspath ./target) DTS=$(realpath device_tree.dts) cargo build --release
	touch $@

firmware.elf: $(CARGO_OUT_DIR)/bootloader
	cp $< $@

firmware.bin: firmware.elf
	riscv64-unknown-elf-objcopy $< $@ -O binary

firmware.mcs: firmware.bin
	vivado -mode batch -source util/generate_mcs.tcl

firmware: firmware.mcs
