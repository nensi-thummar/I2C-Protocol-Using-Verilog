// ============================================================
// master.v — 24512A EEPROM I2C Master (FINAL CORRECT VERSION)
// Protocol:
// WRITE PHASE:
//   START → 0xA0+ACK → ADDR_HI+ACK → ADDR_LO+ACK → DATA+ACK → STOP
//   WAIT 5ms
// READ PHASE:
//   START → 0xA0+ACK → ADDR_HI+ACK → ADDR_LO+ACK → REP-START
//   → 0xA1+ACK → DATA(from EEPROM) → NACK → STOP
// ============================================================

module master(
    input            clk,
    input            rst,
    input            start,
    input      [15:0] word_addr,
    input      [7:0]  write_data,
    output reg [7:0]  read_data,
    output reg        ack_error,
    output reg        done,
    inout             scl,
    inout             sda,
    output reg        busy
);

reg scl_en, sda_en, sda_out;
assign scl = scl_en ? 1'b0 : 1'bz;
assign sda = (sda_en & sda_out) ? 1'b0 : 1'bz;

// ── States ────────────────────────────────────────────────────
parameter IDLE          = 0;
parameter START         = 1;   // write phase START
parameter SEND_DEV_W    = 2;   // send 0xA0
parameter ACK_DEV_W     = 3;
parameter SEND_ADDR_HI  = 4;   // send ADDR[15:8]
parameter ACK_ADDR_HI   = 5;
parameter SEND_ADDR_LO  = 6;   // send ADDR[7:0]
parameter ACK_ADDR_LO   = 7;
parameter SEND_DATA     = 8;   // send write data
parameter ACK_DATA      = 9;
parameter STOP_W        = 10;  // STOP after write
parameter WAIT_5MS      = 11;  // 5ms EEPROM write cycle
// ── Read phase: new START, resend address, then REP-START ─────
parameter START2        = 12;  // new START for read phase
parameter SEND_DEV_W2   = 13;  // send 0xA0 again
parameter ACK_DEV_W2    = 14;
parameter SEND_ADDR_HI2 = 15;  // send ADDR[15:8] again
parameter ACK_ADDR_HI2  = 16;
parameter SEND_ADDR_LO2 = 17;  // send ADDR[7:0] again
parameter ACK_ADDR_LO2  = 18;
parameter REP_START     = 19;  // repeated START
parameter SEND_DEV_R    = 20;  // send 0xA1
parameter ACK_DEV_R     = 21;
parameter READ_DATA     = 22;  // read byte from EEPROM
parameter SEND_NACK     = 23;  // master NACK
parameter STOP_R        = 24;  // STOP after read

(* mark_debug = "true" *) reg [4:0]  state;
(* mark_debug = "true" *) reg [18:0] clk_div;
(* mark_debug = "true" *) reg [3:0]  bit_count;
                          reg [7:0]  shift_reg;
                          reg        ack_bit;
                          reg        clk_div_rst;

parameter WAIT_CYCLES = 19'd499999;  // 5ms at 100MHz

// ── Clock divider ─────────────────────────────────────────────
always @(posedge clk or posedge rst)
begin
    if (rst)
        clk_div <= 0;
    else if (clk_div_rst)
        clk_div <= 0;
    else
        clk_div <= clk_div + 1;
end

// ── Main FSM ──────────────────────────────────────────────────
always @(posedge clk or posedge rst)
begin
    if (rst)
    begin
        state       <= IDLE;
        scl_en      <= 0;
        sda_en      <= 0;
        sda_out     <= 0;
        busy        <= 0;
        done        <= 0;
        ack_error   <= 0;
        shift_reg   <= 0;
        bit_count   <= 0;
        clk_div_rst <= 0;
        ack_bit     <= 0;
        read_data   <= 0;
    end
    else
    begin
        clk_div_rst <= 0;
        done        <= 0;

        case (state)

        // =========================================================
        // IDLE
        // =========================================================
        IDLE:
        begin
            scl_en      <= 0;
            sda_en      <= 0;
            sda_out     <= 0;
            busy        <= 0;
            ack_error   <= 0;
            clk_div_rst <= 1;
            if (start)
            begin
                busy        <= 1;
                clk_div_rst <= 1;
                state       <= START;
            end
        end

        // =========================================================
        // WRITE PHASE
        // =========================================================

        // ── START condition ───────────────────────────────────────
        START:
        begin
            case (clk_div)
            0:   begin scl_en<=0; sda_en<=0; end       // both HIGH
            200: begin sda_en<=1; sda_out<=1; end       // SDA LOW while SCL HIGH
            500: scl_en <= 1;                           // SCL LOW
            999: begin
                    clk_div_rst <= 1;
                    shift_reg   <= 8'hA0;               // 0xA0 = 0x50 Write
                    bit_count   <= 7;
                    state       <= SEND_DEV_W;
                 end
            endcase
        end

        // ── Send 0xA0 ─────────────────────────────────────────────
        SEND_DEV_W:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_DEV_W;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_DEV_W:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_bit;
                    shift_reg <= word_addr[15:8];
                    bit_count <= 7;
                    state     <= SEND_ADDR_HI;
                 end
            endcase
        end

        // ── Send ADDR[15:8] ───────────────────────────────────────
        SEND_ADDR_HI:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_ADDR_HI;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_ADDR_HI:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    shift_reg <= word_addr[7:0];
                    bit_count <= 7;
                    state     <= SEND_ADDR_LO;
                 end
            endcase
        end

        // ── Send ADDR[7:0] ────────────────────────────────────────
        SEND_ADDR_LO:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_ADDR_LO;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_ADDR_LO:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    shift_reg <= write_data;
                    bit_count <= 7;
                    state     <= SEND_DATA;
                 end
            endcase
        end

        // ── Send data byte ────────────────────────────────────────
        SEND_DATA:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_DATA;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_DATA:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    state     <= STOP_W;
                 end
            endcase
        end

        // ── STOP (write) ──────────────────────────────────────────
        // SCL releases HIGH first, then SDA releases HIGH
        STOP_W:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=1; sda_out<=0; end  // SCL low, SDA low
            400: scl_en <= 0;                                  // SCL HIGH
            700: begin sda_en<=0; sda_out<=0; end              // SDA HIGH = STOP
            999: begin clk_div_rst<=1; state<=WAIT_5MS; end
            endcase
        end

        // ── Wait 5ms for EEPROM internal write ────────────────────
        WAIT_5MS:
        begin
            scl_en <= 0;
            sda_en <= 0;
            if (clk_div == WAIT_CYCLES)
            begin
                clk_div_rst <= 1;
                state       <= START2;
            end
        end

        // =========================================================
        // READ PHASE — new START, resend full address, then REP-START
        // =========================================================

        // ── New START ─────────────────────────────────────────────
        START2:
        begin
            case (clk_div)
            0:   begin scl_en<=0; sda_en<=0; end       // both HIGH
            200: begin sda_en<=1; sda_out<=1; end       // SDA LOW while SCL HIGH
            500: scl_en <= 1;                           // SCL LOW
            999: begin
                    clk_div_rst <= 1;
                    shift_reg   <= 8'hA0;               // 0xA0 = 0x50 Write
                    bit_count   <= 7;
                    state       <= SEND_DEV_W2;
                 end
            endcase
        end

        // ── Send 0xA0 again ───────────────────────────────────────
        SEND_DEV_W2:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_DEV_W2;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_DEV_W2:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    shift_reg <= word_addr[15:8];
                    bit_count <= 7;
                    state     <= SEND_ADDR_HI2;
                 end
            endcase
        end

        // ── Send ADDR[15:8] again ─────────────────────────────────
        SEND_ADDR_HI2:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_ADDR_HI2;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_ADDR_HI2:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    shift_reg <= word_addr[7:0];
                    bit_count <= 7;
                    state     <= SEND_ADDR_LO2;
                 end
            endcase
        end

        // ── Send ADDR[7:0] again ──────────────────────────────────
        SEND_ADDR_LO2:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_ADDR_LO2;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_ADDR_LO2:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    state     <= REP_START;   // now do repeated start
                 end
            endcase
        end

        // ── Repeated START ────────────────────────────────────────
        // SDA falls while SCL is HIGH
        REP_START:
        begin
            case (clk_div)
            0:   begin scl_en<=0; sda_en<=0; end        // both released HIGH
            300: begin sda_en<=1; sda_out<=1; end        // SDA LOW while SCL HIGH = Sr
            600: scl_en <= 1;                            // SCL LOW
            999: begin
                    clk_div_rst <= 1;
                    shift_reg   <= 8'hA1;                // 0xA1 = 0x50 Read
                    bit_count   <= 7;
                    state       <= SEND_DEV_R;
                 end
            endcase
        end

        // ── Send 0xA1 ─────────────────────────────────────────────
        SEND_DEV_R:
        begin
            case (clk_div)
            0:   scl_en <= 1;
            200: begin sda_en<=1; sda_out<=~shift_reg[bit_count]; end
            500: scl_en <= 0;
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    if (bit_count==0) state <= ACK_DEV_R;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        ACK_DEV_R:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end
            500: begin scl_en<=0; ack_bit<=sda; end
            999: begin
                    scl_en<=1; clk_div_rst<=1;
                    ack_error <= ack_error | ack_bit;
                    bit_count <= 7;
                    state     <= READ_DATA;   // EEPROM now drives data
                 end
            endcase
        end

        // ── Read data byte from EEPROM ────────────────────────────
        READ_DATA:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=0; end                // SCL low, release SDA
            500: begin scl_en<=0; read_data[bit_count]<=sda; end // SCL high, sample
            800: scl_en <= 1;                                    // SCL low for next bit
            999: begin
                    clk_div_rst <= 1;
                    if (bit_count==0) state <= SEND_NACK;
                    else bit_count <= bit_count - 1;
                 end
            endcase
        end

        // ── Master sends NACK ─────────────────────────────────────
        // sda_out=0 → SDA released HIGH via pullup = NACK
        SEND_NACK:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=1; sda_out<=0; end
            500: scl_en <= 0;
            999: begin scl_en<=1; clk_div_rst<=1; state<=STOP_R; end
            endcase
        end

        // ── STOP (read) ───────────────────────────────────────────
        // SCL releases HIGH first, then SDA releases HIGH
        STOP_R:
        begin
            case (clk_div)
            0:   begin scl_en<=1; sda_en<=1; sda_out<=0; end  // SCL low, SDA low
            400: scl_en <= 0;                                  // SCL HIGH
            700: begin sda_en<=0; sda_out<=0; end              // SDA HIGH = STOP
            999: begin
                    busy        <= 0;
                    done        <= 1;
                    clk_div_rst <= 1;
                    state       <= IDLE;
                 end
            endcase
        end

        default: state <= IDLE;

        endcase
    end
end
endmodule



