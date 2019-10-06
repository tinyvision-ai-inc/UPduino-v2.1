UPDuino v2.1 Device Programming
===============================

Hardware Needed:
* [tinyVision UPDuino v2.1 Board](https://www.tindie.com/products/tinyvision_ai/upduino-v21-low-cost-fpga-board/)

Software Needed:

* [Lattice Diamond/Radiant Programmer Standalone (Diamond v3.9 x64 used for programming instructions)](http://www.latticesemi.com/en/Products/DesignSoftwareAndIP/ProgrammingAndConfigurationSw/Programmer.aspx#_20C94305815A4B3AAAFEA8B83943B751).
Note that Radiant is specific to iCE40 UP devices while Diamond supports other Lattice devices as well.
* [Lattice iCECube2 Software](http://www.latticesemi.com/Products/DesignSoftwareAndIP/FPGAandLDS/iCEcube2.aspx#_4351BE10BA504435B5226390CF5D7D4C)

FPGA Projects Needed:

* [UPDuino v2.1 Blinky LED Design](http://TBD)

Programming (SPI Flash):

1. Plug the UPDuino v2.1 in to your PC using the micro USB port on the board
2. Open the Lattice Diamond Programmer
3. Click `Detect Cable` then `OK`
4. After scanning select `Generic JTAG Device` and `Select iCE40 UltraPlus`
5. Under `Device` click iCE40UP3K and change it to iCE40UP5K
6. Under `Operation` double click `Fast Program` and change `Access Mode:` to `SPI Flash Programming`
7. Select your `*.hex` programming file under `Programming file`.
8. Configure the following `SPI Flash Options`
    a. Winbond (Numonyx for the yellow v2.0 UPDuino)
    b. TBD (SPI-N25Q032 for the yellow v2.0 UPduino)
    c. TBD (8-pin VDFPN8 for the yellow v2.0 UPduino)
9. Click `Load from File` under `SPI Programming` to get load size
10. Click `Design` -> `Program`

Project Synthesis (Compiling) and bitstream (Firmware) generation:

1. Unzip UPDUINO21_RGB_LED_BLINK.zip
2. Open Lattice iCECube2 Software
3. Double click `Open Project`
4. Navigate to *\UPDUINO_RGB_LED_BLINK\rgb\rgb_sbt.project and `Open`
5. Double click `Run Synplify Pro Synthesis`
6. Right click on `Run P&R` and left click `Run Bitmap`

    * Note – this will run all remaining synthesis steps including place, route and bitmap generation.
    * Generated bitstream will be loaded in the `*\rgb\rgb_Implmnt\sbt\outputs\bitmap folder`
