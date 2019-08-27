#FPGA build instructions
The FPGA can be built either using the Lattice Radiant toolchain that can be downloaded [here] (http://www.latticesemi.com/en/Products/DesignSoftwareAndIP) or the open source icestorm toolchain which can be downloaded [here](https://github.com/cliffordwolf/icestorm).

The FTDI programmer has a different USB ID than the default in teh icestorm toolchain. Programming the board can be done using the following command:
    iceprog.exe -d i:0x0403:0x6014 <bitfile name>
