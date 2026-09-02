# Configurable-Peripheral-Subsystem-for-an-SoC
Modern System-on-Chip (SoC) architectures rely heavily on standardized on-chip communication fabrics to connect high-performance processing elements with diverse peripheral components. While central processing units (CPUs) handle heavy computational workloads, peripheral subsystems manage low-level data ingestion, serial communications, synchronization, and external device control.

This project entails the complete RTL design, microarchitectural integration, and rigorous UVM-based verification of a Configurable Memory-Mapped Peripheral Subsystem tied together by an AMBA APB3/APB4 (Advanced Microcontroller Bus Architecture - Advanced Peripheral Bus) interconnect. Tailored for advanced VLSI and digital design engineers, this subsystem bridges the operational gap between high-speed internal system buses and slower, asynchronous or synchronous external communication channels.

The subsystem integrates four primary intellectual property (IP) blocks:

A Multi-Channel Synchronous FIFO: Equipped with programmable watermarks and elastic buffer control to eliminate data loss and manage cross-domain or clock-rate disparities.

A Full-Duplex Custom UART: Featuring an oversampled receiver, programmable baud rate generator, and dedicated control/status registers.

An SPI Master Interface: Supporting configurable clock polarity (CPOL), clock phase (CPHA), and multi-bit shift registers.

A Nested Interrupt Controller (NIC): Managing priority-encoded hardware interrupts across all integrated modules before generating a unified interrupt request to a host CPU.

By combining rigorous RTL design practices in SystemVerilog with a complete Universal Verification Methodology (UVM) testbench, this project demonstrates end-to-end competency in digital ASIC design, bus protocol compliance, hardware state machine development, and functional verification.

## APB Wrapper Added

The project now includes an APB peripheral wrapper in [peripheral_subsystem_apb.sv](C:/Users/ASUS/OneDrive/SOC_PROJECT/Configurable-Peripheral-Subsystem-for-an-SoC/peripheral_subsystem_apb.sv), enabling memory-mapped CPU access for SPI TX/RX buffering and runtime SPI configuration.
For direct SoC hookup with conventional APB signal names, use [peripheral_subsystem_soc_top.sv](C:/Users/ASUS/OneDrive/SOC_PROJECT/Configurable-Peripheral-Subsystem-for-an-SoC/peripheral_subsystem_soc_top.sv).

### Register Map (Word Offsets)

- `0x0` **TX Data / FIFO Write** (Write-Only): writing `PWDATA[7:0]` pushes one byte into SPI TX FIFO when not full.
- `0x4` **RX Data / FIFO Read** (Read-Only): reading returns `PRDATA[7:0]` and pops one byte from SPI RX FIFO when not empty.
- `0x8` **Control Register** (Read/Write): `spi_cpol_cpha` in `[1:0]`, `spi_clk_div` in `[9:2]`.
- `0xC` **Status Register** (Read-Only): `[0] tx_empty`, `[1] tx_full`, `[2] rx_empty`, `[3] rx_full`, `[4] spi_busy`.

### APB Verification Testbench

A dedicated register-map testbench is provided in [peripheral_subsystem_apb_tb.sv](C:/Users/ASUS/OneDrive/SOC_PROJECT/Configurable-Peripheral-Subsystem-for-an-SoC/peripheral_subsystem_apb_tb.sv).
