# UPduino v2.1

<img src="./assets/images/UPduino_v2.1_front.jpg" alt="UPduino v2.1 Front" width="400"/>

## UPDuino v2.1: PCB Design Files, Designs, Documentation

The UPDuino v2.1 is a small, low cost FPGA board, built with license from Lattice Semiconductor. The board features an on-board FPGA programmer, flash and LED with all pins brought out to easy to use 0.1" header pins for fast prototyping.

The tinyVision.ai UPduino v2.1 Board Features:

* Lattice UltraPlus ICE40UP5K FPGA with 5.3K LUTs, 1Mb SPRAM, 120Kb DPRAM, 8 Multipliers
* FTDI FT232H USB to SPI Device
* 30 GPIO on 0.1” headers
* 4MB SPI Flash
* RGB LED
* On board 3.3V and 1.2V Regulators, can supply 3.3V to your project
* Open source schematic and layout using Eagle PCB design tools
* Integrated into the open source [APIO toolchain](https://github.com/FPGAwars/apio)
* Improved USB footprint to minimize connectors ripping off the board

### Please fill out the [next generation survey](https://www.surveymonkey.com/r/HH536D8) to suggest improvements to this board. We really appreciate the feedback and will make improvements as business permits!

You can buy the board here:<a href="https://www.tindie.com/stores/tinyvision_ai/?ref=offsite_badges&utm_source=sellers_vr2045&utm_medium=badges&utm_campaign=badge_medium"><img src="https://d2ss6ovg47m0r5.cloudfront.net/badges/tindie-mediums.png" alt="I sell on Tindie" width="150" height="78"></a>

## Useful links
* [osresearch](https://github.com/osresearch/up5k): large collection of very useful code and a good overview.
* [UPduino FPGA tutorial using APIO](https://blog.idorobots.org/entries/upduino-fpga-tutorial.html)
* [A very detailed blog on implementing a RISCV in the FPGA](https://pingu98.wordpress.com/2019/04/08/how-to-build-your-own-cpu-from-scratch-inside-an-fpga/)

## Differences between the v2.0 and v2.1 hardware
The original design for the UPduino v2.0 was from [GnarlyGrey](http://gnarlygrey.com/). The design for the UPduino was transferred to tinyVision.ai by Lattice Semiconductor recently. The board is already in use for a variety of projects but some improvements were necessary to make this more production friendly. Note that this exercise was a minimal change only!
* Changed soldermask to black to make it easy to identify the v2.0 from v2.1 and also for branding purposes. Added tinyVision logo to silkscreen.
* Replaced micro USB surface mount connector with through hole parts. This reduces the probability of the USB connector ripping off from the PWB.
* Unified resistor and capacitor sizes to 0603 from a mix of 0603/0805 footprints
* Added fiducials to the board for manufacturability
* LED and resonator went end of life. Replaced the LED with [this](https://www.mouser.com/ProductDetail/Broadcom-Avago/ASMB-MTB0-0A3A2?qs=%2Fha2pyFaduiVySQcEVUF3g99inKvemcQFBZprfU%2FW0p9YdxM%252BOGCOQ%3D%3D) one and the resonator with [this](https://www.mouser.com/ProductDetail/Murata-Electronics/CSTNE12M0G550000R0?qs=sGAEpiMZZMsBj6bBr9Q9aVicrFFkOfIYlp58nnUM76JPeseMdQedBQ%3D%3D) one.
* Flash used is the [Winbond W25Q32JVSNIM](https://www.mouser.com/ProductDetail/Winbond/W25Q32JVSNIM?qs=sGAEpiMZZMtI%252BQ06EiAoG4%252BhDIVn9lGKlH%2FgDg3lStQ%3D)
* Boards are built in Carlsbad, CA from parts sourced from Digikey/Mouser so known good, non-recycled parts are used. We use a cool [vapor phase reflow](https://www.westfloridacomponents.com/blog/vapor-phase-reflow-soldering/)!
* Testing: Each board is inspected using [AOI](https://en.wikipedia.org/wiki/Automated_optical_inspection) to ensure all parts are placed properly. Each board is programmed with a blinking LED to ensure the parts come up and the LED is alive. Also the FTDI EEPROM is programmed with some details.

#### Further planned HW changes:
Will depend on volume of orders.
* Move micro USB connector inboard a bit to improve panelization
* Change design to KiCAD for truly open source
