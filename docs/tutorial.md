# Tutorial

## Hardware Supported

To run this tutorial, you will need one of the supported FPGA boards. Currently, the following FPGAs
are supported:
* Nexys A7
* Genesys 2

For this tutotial you will also need a microSD card (and a card reader).

## Environment Setup

Ensure Python 3, Make and GCC toolchains are installed. They should be available from your distribution. If you are using a Debian-based system,
you can install them with the following command:
```bash
sudo apt-get install python3 build-essential
```

Hardware synthesis and implementation needs the following extra tools:
* Vivado
* [FuseSoC](https://github.com/olofk/fusesoc)
* [Edalize](https://github.com/olofk/edalize)
* [Mako](https://github.com/sqlalchemy/mako)

Vivado needs to be obtained from [Xilinx](https://www.xilinx.com/support/download.html). A license may be needed depending on your FPGA. Please refer to Xilinx documentation for more information. Please ensure that `vivado` is in your PATH.
Please use a Vivado version that is at least v2020.2.

FuseSoc, Edalize and Mako can be installed with PIP. Change the working directory to the root of the project, and run:
```bash
pip3 install -r python-requirements.txt
```

Firmware and software compilatin needs the following tools:
* Device tree compiler
* Flex and Bison
* GCC toolchain for cross-compilation
* Rustc and Cargo

Device tree compiler, flex and bison should be available from your distribution. If you are using a Debian-based system,
you can install them with the following command:
```bash
sudo apt-get install device-tree-compiler flex bison
```

If you are using a Debian-based system, RISC-V cross compilers can also be fetched using apt-get:
```bash
sudo apt-get install gcc-riscv64-linux-gnu
```
If you want to build the cross compiler yourself, you can follow [this guide](https://wiki.osdev.org/GCC_Cross-Compiler)
and compile for target riscv64-unknown-linux-gnu.

The Rust toolchain can obtained from [Rustup](https://rustup.rs/).
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
Nightly compiler is required, and riscv64imac-unknown-none-elf target is needed. Though this should
normally be automatically installed by Rustup when compiling the firmware for the first time since
we have provided `rust-toolchain.toml` file.

## Building Bitstream and Firmware

Before building, first ensure that all submodules are up to date:
```bash
git submodule update --init --recursive
```

Then cd into the directory that corresponds to your FPGA board, e.g. `cd nexys_a7`.

The bitstream can be built using `make bitstream`. The firmware can be built using `make firmware`.

## Building Kernel and Distro Image

Kernel and distro images are agnostic to different FPGA boards.

In the root directory of the project, the kernel can be built using `make vmlinux`.

Debian image can be built using `make rootfs.img`. It should be noted that bootstrapping Debian image requires root privileges and a Debian-based system.

## Preparing the SD Card

Connect the SD card reader to your machien and insert the microSD card. Assuming the card is located at `/dev/mmcblk0`, then you can write the Debian image to the microSD card:
```bash
sudo dd if=rootfs.img of=/dev/mmcblk0 bs=1M
```
Note that this will overwrite the contents on the microSD card.

Then you can expand the file system to the full size of the card:
```bash
sudo resize2fs /dev/mmcblk0
```

Next mount the file system and copy the kernel into the file system:
```bash
sudo mount /dev/mmcblk0 /mnt
sudo cp vmlinux /mnt
sudo umount /mnt
```

The card should be ready. You can now eject the card and insert it onto the FPGA board.

## Programming the FPGA

Now here is the final step. The firmware needs to be programmed onto the on-board flash memory.

Ensure that the board is connected to your machine, drivers are installed and the Xilinx HW server is running, and run
```bash
make program-flash-firmware
```
in the board-specific directory.

Open your TTY program of choice on the FPGA-bound link with baud 230400, and run
```bash
make program-bitstream
```
to load the bitstream onto the FPGA.

If everything goes well you should start to see output from the firmware and Linux booting!

If you want to persist the bitstream, you can program it along with the firmware to the flash with
```bash
make program-flash
```
You may need to switch the jumper on the board to switch the source from QSPI.