PREFIX = riscv64-unknown-linux-gnu-

linux/.config:
	cp data/linux.config $@

vmlinux: linux/.config
	cd linux; $(MAKE) CROSS_COMPILE=$(PREFIX) ARCH=riscv
	$(PREFIX)strip linux/vmlinux -o $@

vmlinux.gz: vmlinux
	gzip < $< > $@

rootfs.img: data/debian_packages.txt
	util/create_rootfs.sh
