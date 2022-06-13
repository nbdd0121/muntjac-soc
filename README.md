# Muntjac SoC

This repository contains a simple SoC that builds upon [muntjac](https://github.com/lowRISC/muntjac) that can be used out-of-the-box.

For a detailed walkthough about how to build/use this project, please check the [tutorial](./docs/tutorial.md).

## Components

The SoC contains the following components out of the box:
* 2 Muntjac cores
* Interrupt controller and timer (PLIC and CLINT)
* Flash memory controller[^1] (work in XIP mode)
* DDR memory controller[^1]
* UART 16550[^1]
* SD card controller
* *(optional)* Ethernet controller[^2]

[^1]: Xilinx IP that comes with Vivado, but not open source
[^2]: Xilinx IP, not open source, separate license required

## Supported Targets

Currently two FPGA boards are supported:
* Nexys A7
* Genesys 2

## Licensing

Unless otherwise noted, everything in this repository is dual-licensed in the MIT license and the Apache
License, Version 2.0. See [LICENSE-APACHE](./LICENSE-APACHE), [LICENSE-MIT](./LICENSE-MIT) for details.
