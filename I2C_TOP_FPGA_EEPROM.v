// ============================================================
// i2c_top.v — 24512A EEPROM Write + Readback
// Write 0xA5 to address 0x0010, read back, compare
// Success : LD0-LD3 all ON
// Mismatch: RGB red all ON
// NACK err: LD0 blinks (ack_error latched)
// ============================================================

module i2c_top(
    input        clk,
    input        btn0,      // RST   — D9
    input        btn1,      // START — C9
    inout        ja0,       // SDA   — G13
    inout        ja1,       // SCL   — B11
    output [3:0] led,
    output [3:0] led_r
);

localparam [15:0] WORD_ADDR  = 16'h0010;
localparam [7:0]  WRITE_BYTE = 8'hA5;

wire       busy, done, ack_error;
wire [7:0] read_data;

// ── Result latch ─────────────────────────────────────────────
reg        verify_ok;
reg        verify_fail;

// ── Debounce RST (btn0) ──────────────────────────────────────
reg [19:0] rst_cnt;
reg        rst_clean;

always @(posedge clk or posedge btn0)
begin
    if (btn0)
    begin
        rst_cnt   <= 0;
        rst_clean <= 1;
    end
    else
    begin
        if (rst_clean)
        begin
            rst_cnt <= rst_cnt + 1;
            if (rst_cnt == 20'd999999)
            begin
                rst_clean <= 0;
                rst_cnt   <= 0;
            end
        end
    end
end

// ── Debounce START (btn1) ────────────────────────────────────
reg [20:0] db_cnt;
reg        btn1_clean;
reg        btn1_prev;

always @(posedge clk or posedge rst_clean)
begin
    if (rst_clean)
    begin
        db_cnt     <= 0;
        btn1_clean <= 0;
        btn1_prev  <= 0;
    end
    else
    begin
        btn1_prev <= btn1_clean;
        if (btn1 == btn1_clean)
            db_cnt <= 0;
        else
        begin
            db_cnt <= db_cnt + 1;
            if (db_cnt == 21'd1999999)
            begin
                btn1_clean <= btn1;
                db_cnt     <= 0;
            end
        end
    end
end

wire start_pulse = btn1_clean & ~btn1_prev;

// ── Verify result on done pulse ──────────────────────────────
always @(posedge clk or posedge rst_clean)
begin
    if (rst_clean)
    begin
        verify_ok   <= 0;
        verify_fail <= 0;
    end
    else if (done)
    begin
        if (!ack_error && read_data == WRITE_BYTE)
            verify_ok   <= 1;
        else
            verify_fail <= 1;
    end
end

// ── Master instantiation ─────────────────────────────────────
master u_master (
    .clk        (clk),
    .rst        (rst_clean),
    .start      (start_pulse),
    .word_addr  (WORD_ADDR),
    .write_data (WRITE_BYTE),
    .read_data  (read_data),
    .ack_error  (ack_error),
    .done       (done),
    .scl        (ja1),
    .sda        (ja0),
    .busy       (busy)
);

// ── LEDs ─────────────────────────────────────────────────────
// All 4 LEDs ON  = write+read verified OK
// All 4 RGB red  = data mismatch
// LD0 only       = busy (transaction in progress)
assign led   = verify_ok   ? 4'b1111 :
               busy        ? 4'b0001 : 4'b0000;

assign led_r = verify_fail ? 4'b1111 : 4'b0000;

endmodule



