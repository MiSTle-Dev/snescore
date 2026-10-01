// this is basically hello.img but takes up less space

module test_loader (
    input clk,
    input resetn,
    output reg [7:0] dout,
    output reg dout_valid,
    input dout_ready,
    output loading,
    output fail
);

// PeterLemon tests, 32KB
// localparam SIZE = 33280;
// localparam string FILE = "roms/CPUADC.hex";
// localparam string FILE = "roms/SPC700ADC.hex";
// localparam string FILE = "roms/SPC700AND.hex";
// localparam string FILE = "roms/SPC700ORA.hex";
// localparam string FILE = "roms/memtest.hex";

// 64KB ROMS
// localparam SIZE=66048;
// localparam string FILE = "roms/sram_4.hex";
// localparam string FILE = "roms/hvdma_max.hex";
// localparam string FILE = "roms/div_behavior.hex";
// localparam string FILE = "roms/div_timings.hex";
// localparam string FILE = "roms/mul_behavior.hex";
// localparam string FILE = "roms/mul_timings.hex";

// 96KB ROMS
// localparam SIZE = 98816;
///localparam string FILE = "roms/HiColor575Myst.hex";
// localparam string FILE = "roms/MosaicMode3.hex";

// The runtime-selected image may be any size up to 4 MiB. Hex files used by
// the simulator contain one byte per line, so determine the actual size at
// startup instead of sending a fixed-size image to the SNES core.
localparam integer MAX_SIZE = 4*1024*1024;
`ifdef SIM_ROM_FILE
localparam string DEFAULT_FILE = `SIM_ROM_FILE;
`else
localparam string DEFAULT_FILE = "roms/hello.hex";
`endif
// localparam string FILE = "roms/hello2.hex";
// localparam string FILE = "roms/textbuffer-hello-world.hex";
// localparam string FILE = "roms/Perspective.hex";
// localparam string FILE = "roms/test_dmavalid.hex";
// localparam string FILE = "roms/test_irq4200.hex";
// localparam string FILE = "roms/test_math.hex";
// localparam string FILE = "roms/demo_irq.hex";
// localparam string FILE = "roms/dsp1demo.hex";
// localparam string FILE = "roms/SuperFX.hex";

// 512KB roms
// localparam SIZE = 524800;
// localparam string FILE = "roms/inidisp_extend_vblank.hex";
// localparam string FILE = "roms/superbomberman.hex";

// 256KB ROMS
//localparam SIZE = 262656;
//localparam string FILE = "roms/snes_10.hex";
// localparam string FILE = "roms/hdma-textbox-wipe.hex";
// localparam string FILE = "roms/window-precalculated-symmetrical.hex";
// localparam string FILE = "roms/gradient-test.hex";

// examples
// localparam string FILE = "roms/window-shapes-single.hex";
// localparam string FILE = "roms/hdma-double-buffered-indirect-shear.hex";
// localparam string FILE = "roms/hdma-double-buffered-parallax.hex";
// localparam string FILE = "roms/hdma-indirect-repeating-pattern.hex";
// localparam string FILE = "roms/hdma-to-cgram.hex";
// localparam string FILE = "roms/vram-writes-without-dma.hex";

// effects
// localparam string FILE = "roms/vmain-vertical-scrolling.hex";
// localparam string FILE = "roms/repeating_hdma_pattern.hex";
// localparam string FILE = "roms/window-shapes-single.hex";
// localparam string FILE = "roms/window-precalculated-single.hex";
// localparam string FILE = "roms/window-precalculated-symmetrical.hex";

// glitches
// localparam string FILE = "roms/setini-early-read-obj.hex";

// vmain-address-remapping
// localparam string FILE = "roms/vmain-1bpp-no-remapping.hex";
// localparam string FILE = "roms/vmain-8bpp-with-remapping.hex";

// 3MB ROM
// localparam SIZE = 3146240;
// localparam string FILE = "roms/super_metroid.hex";


reg [7:0] rom [0:MAX_SIZE-1];
reg [21:0] addr;
reg finished;
reg pad_sent;
integer rom_size;
integer fd;
integer line_len;
integer count;
string file_name;

initial begin
   file_name = DEFAULT_FILE;
   if ($value$plusargs("ROM=%s", file_name)) begin end

   rom_size = 0;
   fd = $fopen(file_name, "r");
   if (fd == 0) begin
       $display("ERROR: cannot open ROM hex file %s", file_name);
       $finish;
   end
   while (!$feof(fd)) begin
       line_len = $fgets(count, fd);
       if (line_len > 0)
           rom_size = rom_size + 1;
   end
   $fclose(fd);
   if (rom_size > MAX_SIZE) begin
       $display("ERROR: ROM %s has %0d bytes; maximum is %0d", file_name, rom_size, MAX_SIZE);
       $finish;
   end
   if (!(rom_size & 512)) begin
       $display("ERROR: ROM %s is missing the 512 byte rom header", file_name);
       $finish;
   end
   
   $display("Loading ROM %s (%0d bytes)", file_name, rom_size);
   $readmemh(file_name, rom, 0, rom_size - 1);
end

// Keep the SNES paused until the final byte has been consumed and its
// outstanding SDRAM write has been acknowledged. The next-byte address alone
// reaches rom_size before the final byte is accepted.
assign loading = !finished;
assign fail    = 1'b0;

always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        addr <= 0;
        dout_valid <= 0;
        finished <= 0;
        pad_sent <= 0;

    end else begin
        if ({10'b0, addr} >= rom_size && !dout_valid && dout_ready)
            finished <= 1;
        if (!dout_valid || dout_ready) begin
            if ({10'b0, addr} >= rom_size) begin
                if (rom_size > 512 && rom_size[0] && !pad_sent) begin
                    // The controller writes 16-bit words. Complete an odd
                    // final byte with an erased-ROM high byte.
                    dout <= 8'hff;
                    dout_valid <= 1;
                    pad_sent <= 1;
                end else
                    dout_valid <= 0;
            end else begin
                dout <= rom[addr];
                dout_valid <= 1;
                addr <= addr + 1;
                if (addr == 63)     // header is 64 bytes long
                    addr <= 512;
            end
        end
    end
end

endmodule
