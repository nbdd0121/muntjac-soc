LD_VERSION := $(shell riscv64-unknown-linux-gnu-ld -v 2>/dev/null)

ifdef LD_VERSION
PREFIX = riscv64-unknown-linux-gnu-
else
PREFIX = riscv64-linux-gnu-
endif

linux/.config:
	cp data/linux.config $@

vmlinux: linux/.config
	cd linux; $(MAKE) CROSS_COMPILE=$(PREFIX) ARCH=riscv
	$(PREFIX)strip linux/vmlinux -o $@

vmlinux.gz: vmlinux
	gzip < $< > $@

rootfs.img: data/debian_packages.txt
	touch -a $@
	util/create_rootfs.sh

CARGO_OUT_DIR=$(realpath .)/build/release

# Files colleted by Cargo
-include $(CARGO_OUT_DIR)/linker.d

$(CARGO_OUT_DIR)/linker:
	cd tools/linker; CARGO_TARGET_DIR=$(abspath ./build) cargo build --release
	touch $@

build/linker: $(CARGO_OUT_DIR)/linker
	cp $< $@
