LD_VERSION := $(shell riscv64-unknown-linux-gnu-ld -v 2>/dev/null)

ifdef LD_VERSION
PREFIX = riscv64-unknown-linux-gnu-
else
PREFIX = riscv64-linux-gnu-
endif

default: firmware

.PHONY: default firmware project bitstream program-flash-firmware program-flash

FORCE:

../build/linker: FORCE
	@$(MAKE) -C .. -q build/linker || $(MAKE) -C .. build/linker

CARGO_OUT_DIR=$(realpath .)/target/riscv64imac-unknown-none-elf/release

device_tree.dts:
	cp data/device_tree.dts .

# Files colleted by Cargo
-include $(CARGO_OUT_DIR)/bootloader.d

$(CARGO_OUT_DIR)/bootloader: ../build/linker device_tree.dts
	cd ../firmware; CARGO_TARGET_DIR=$(abspath ./target) DTS=$(realpath device_tree.dts) cargo build --release
	touch $@

firmware.elf: $(CARGO_OUT_DIR)/bootloader
	cp $< $@

firmware.bin: firmware.elf
	$(PREFIX)objcopy $< $@ -O binary

firmware.mcs: firmware.bin
	vivado -notrace -mode batch -source util/generate_mcs.tcl -tclargs nobit

firmware: firmware.elf

PROJECT_DIR=build/garyguo.net_systems_muntjac_soc_0.1/genesys_2-vivado
PROJECT_NAME=garyguo.net_systems_muntjac_soc_0.1
PROJECT=$(PROJECT_DIR)/$(PROJECT_NAME).xpr

# Files collected by FuseSoC
fusesoc-deps=
-include $(PROJECT_DIR)/core-deps.mk

# Vivado can handle changed SystemVerilog files, so filter them out
# TODO: How about generated files
fusesoc-deps-sv=$(filter %.sv %.svh %.xdc,$(fusesoc-deps))
fusesoc-deps-no-sv=$(filter-out %.sv %.svh %.xdc,$(fusesoc-deps))

project: $(PROJECT)

$(PROJECT): $(fusesoc-deps-no-sv)
	fusesoc --cores-root=.. run --setup --target=genesys_2 --no-export garyguo.net:systems:muntjac_soc
	$(MAKE) -C $(PROJECT_DIR) $(PROJECT_NAME).xpr

bitstream: bitstream.bit

$(PROJECT_DIR)/$(PROJECT_NAME).bit: $(PROJECT) $(fusesoc-deps-sv)
	cd $(PROJECT_DIR); vivado -notrace -mode batch -source $(realpath ../util/generate_bitstream.tcl) $(PROJECT_NAME).xpr

bitstream.bit: $(PROJECT_DIR)/$(PROJECT_NAME).bit
	cp $< $@

bitstream.mcs: firmware.bin bitstream.bit
	vivado -notrace -mode batch -source util/generate_mcs.tcl -tclargs bit

program-flash-firmware: firmware.mcs
	PART="xc7k325tffg900-2" CFGMEM_PART="s25fl256sxxxxxx0-spi-x1_x2_x4" PROGRAM="$<" vivado -notrace -mode batch -source ../util/program_flash.tcl

program-flash: bitstream.mcs
	PART="xc7k325tffg900-2" CFGMEM_PART="s25fl256sxxxxxx0-spi-x1_x2_x4" PROGRAM="$<" vivado -notrace -mode batch -source ../util/program_flash.tcl

program-bitstream: bitstream.bit
	PART="xc7k325tffg900-2" PROGRAM="$<" vivado -notrace -mode batch -source ../util/program_bitstream.tcl
