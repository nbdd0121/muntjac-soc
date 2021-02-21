default: firmware.bin

.PHONY: default firmware.elf

firmware.elf:
	cargo build --release
	cp target/riscv64imac-unknown-none-elf/release/bootloader $@

firmware.bin: firmware.elf
	riscv64-unknown-elf-objcopy $< $@ -O binary

firmware.mem: firmware.bin
	cp $< firmware.bin.tmp
	echo 'PADDING' >> firmware.bin.tmp
	echo '@0000' > $@
	xxd -g 8 -c 8 firmware.bin.tmp | \
		awk -e '{print substr($$2,15,2)substr($$2,13,2)substr($$2,11,2) \
		substr($$2,9,2)substr($$2,7,2)substr($$2,5,2)substr($$2,3,2)     \
		substr($$2,1,2);}' >> $@

program: firmware.mem
	cd .. &&  /mnt/c/Windows/System32/cmd.exe /c update.bat
