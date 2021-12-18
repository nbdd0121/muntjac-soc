PREFIX = riscv64-unknown-linux-gnu-

vmlinux: linux/.config
	cd linux; $(MAKE) CROSS_COMPILE=$(PREFIX) ARCH=riscv
	$(PREFIX)strip linux/vmlinux -o $@

vmlinux.gz: vmlinux
	gzip < $< > $@

linux/.config:
	cp data/linux.config $@
