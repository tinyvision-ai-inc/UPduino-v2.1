# FPGA build instructions
The FPGA can be built either using the Lattice Radiant toolchain that can be downloaded [here](http://www.latticesemi.com/en/Products/DesignSoftwareAndIP) or the open source icestorm toolchain which can be downloaded [here](https://github.com/cliffordwolf/icestorm).

## Instructions for icestorm toolchain programming
The FTDI programmer has a different USB ID than the default in the icestorm toolchain. Programming the board can be done using the following command:

    iceprog.exe -d i:0x0403:0x6014 <bitfile name>

## Make UPduino board writable without sudo (Linux only)
Copy included upduinov2.rules to /etc/udev/rules.d and then plug the UPduino board into your PC
    sudo cp UPduino-v2.1/RTL/src/upduinov2.rules /etc/udev/rules.d

## Build rgb_blink.v demo with icestorm
    cd UPduino-v2.1/RTL/src
    make
    make flash

