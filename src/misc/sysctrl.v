/*
    sysctrl.v
 
    generic system control interface from/via the MCU

    TODO: This is currently very core specific. This needs to be
    generic for all cores.
*/

module sysctrl (
  input		    clk,
  input		    reset,

  input		    data_in_strobe,
  input		    data_in_start,
  input [7:0]	    data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output	    int_out_n,
  input [7:0]	    int_in,
  output reg [7:0]  int_ack,

  input [1:0]	    buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit color to e.g. be used to drive the ws2812

  // IO port interface
  output reg	    port_out_strobe,
  input		    port_out_available,
  input [7:0]	    port_out_data,
  output reg	    port_in_strobe,
  output reg [7:0]  port_in_data,
		
  // values that can be configured by the user
  output reg [1:0]  system_chipset,
  output reg	    system_memory,
  output reg	    system_video,
  output reg [1:0]  system_reset,
  output reg [1:0]  system_scanlines,
  output reg [1:0]  system_volume,
  output reg	    system_wide_screen,
  output reg [1:0]  system_floppy_wprot,
  output reg	    system_cubase_en,
  output reg [1:0]  system_port_mouse,
  output reg	    system_tos_slot
);

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;
   
// reverse data byte for rgb   
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3], 
                           data_in[4], data_in[5], data_in[6], data_in[7] };

// coldboot flash and system interrupt   
reg coldboot = 1'b1;   
reg sys_int = 1'b1;

// the system cobtrol interrupt or any other interrupt (e,g sdc, hid, ...)
// activates the interrupt line to the MCU by pulling it low
assign int_out_n = (int_in != 8'h00 || sys_int)?1'b0:1'b1;
   
reg port_out_availableD;
reg [7:0] data_out_reg;   
   
// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;      
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset
      sys_int = 1'b1;       // coldboot interrupt

      port_out_strobe <= 1'b0;
      port_in_strobe <= 1'b0;
      
      // OSD value defaults. These should be sane defaults, but the MCU
      // will very likely override these early
      system_chipset <= 2'd0;       // regular ST
      system_memory <= 1'b0;        // 4 MB
      system_video <= 1'b0;         // color
      system_scanlines <= 2'b00;    // no scanlines
      system_volume <= 2'b00;       // mute
      system_wide_screen <= 1'b0;   // normal video 
      system_floppy_wprot <= 2'b00; // floppy not write protected
      system_cubase_en <= 1'b0;     // no cubase dongle
      system_port_mouse <= 2'b00;   // mouse on usb -> db9 joystick
      system_tos_slot <= 1'b0;      // primary tos slot
   end else begin
      int_ack <= 8'h00;
      port_out_strobe <= 1'b0;
      port_in_strobe <= 1'b0;

      // iack bit 0 acknowledges the system control interrupt
      if(int_ack[0]) sys_int <= 1'b0;      
            
      // (further) data has just become available, so raise interrupt
      port_out_availableD <= port_out_available;      
      if(port_out_available && !port_out_availableD)
	sys_int <= 1'b1;
      
      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd1;
            command <= data_in;
        end else if(state != 4'd0) begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                // return some pattern that would not appear randomly
	            // on e.g. an unprogrammed device
                if(state == 4'd1) data_out <= 8'h5c;
                if(state == 4'd2) data_out <= 8'h42;
                if(state == 4'd3) data_out <= 8'h01;   // core id 1 = Atari ST
            end
	   
            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd1) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd1) color[15: 8] <= data_in_rev;
                if(state == 4'd2) color[ 7: 0] <= data_in_rev;
                if(state == 4'd3) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
                data_out <= { 6'b000000, buttons };;
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
                // second byte can be any character which identifies the variable to set 
                if(state == 4'd1) id <= data_in;

                if(state == 4'd2) begin
                    // Value "C": chipset ST(0), MegaST(1) or STE(2)
                    if(id == "C") system_chipset <= data_in[1:0];
                    // Value "M": 4MB(0) or 8MB(1)
                    if(id == "M") system_memory <= data_in[0];
                    // Value "V": color(0) or monochrome(1)
                    if(id == "V") system_video <= data_in[0];
                    // Value "R": coldboot(3), reset(1) or run(0)
                    if(id == "R") system_reset <= data_in[1:0];
                    // Value "S": scanlines none(0), 25%(1), 50%(2) or 75%(3)
                    if(id == "S") system_scanlines <= data_in[1:0];
                    // Value "A": volume mute(0), 33%(1), 66%(2) or 100%(3)
                    if(id == "A") system_volume <= data_in[1:0];
                    // Value "W": normal 4:3 screen (0), wide 16:9 screen (1)
                    if(id == "W") system_wide_screen <= data_in[0];
                    // Value "P": floppy write protecion None(0), A(1), B(2) both(3)
                    if(id == "P") system_floppy_wprot <= data_in[1:0];
                    // Value "Q": enable (1) or disable (0) Cubase dongle(s)
                    if(id == "Q") system_cubase_en <= data_in[0];
                    // Value "J": USB Mouse(0), DB9/Atari ST(1) or DB9/Amiga(2)
                    if(id == "J") system_port_mouse <= data_in[1:0];
                    // Value "T": Primary(0) TOS slot or Secondary(1)
                    if(id == "T") system_tos_slot <= data_in[0];
                end
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                // second byte acknowleges the interrupts
                if(state == 4'd1) int_ack <= data_in;

	        // interrupt[0] notifies the MCU of a FPGA cold boot e.g. if
                // the FPGA has been loaded via USB
                data_out <= { int_in[7:1], sys_int };
            end
	   
            // CMD 6: read system interrupt source
            if(command == 8'd6) begin
	        // bit[0]: coldboot flag
	        // bit[1]: port data is available
                data_out <= { 6'b000000, port_out_available, coldboot };
	        // reading the interrupt source acknowledges the coldboot notification
	        if(state == 4'd1) coldboot <= 1'b0;            
	    end

            // CMD 7: read port output status and data
            if(command == 8'd7) begin
	        // first byte returns data availability flag
                if(state == 4'd1) begin
		   data_out <= { 7'd0, port_out_available };
		   // latch data as it may become available after this first 
		   // access but before reading the second byte. We'd the ack'
		   // a byte which we previously haven't been indicated as valid.
		   data_out_reg <= port_out_data;
		   // reading the byte ack's the mfp's fifo, but only if data
		   // was actually available
		   if(port_out_available) port_out_strobe <= 1'b1;
	        end else if(state == 4'd2)
		  data_out <= data_out_reg;		   
            end // if (command == 8'd7)
	   
            // CMD 8: write port data
            if(command == 8'd8) begin
               if(state == 4'd1) begin
		  port_in_data <= data_in;
		  port_in_strobe <= 1'b1;
	       end
	    end
	end
      end // if (data_in_strobe)
   end
end
    
endmodule
