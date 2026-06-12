module i2c_tb;
  reg        clk, reset, in, rw;
  reg  [7:0] din;
  reg  [6:0] add;
  wire [7:0] dout;
  tri        sda;
  wire       scl;
  reg  [7:0] slave_data;
  reg  [2:0] slave_bit_cnt;
  reg        slave_sda_drive;

  pullup(sda);

  i2c DUT(.clk(clk),.reset(reset),.in(in),.rw(rw),
          .din(din),.add(add),.dout(dout),.sda(sda),.scl(scl));

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, i2c_tb);
    $dumpvars(1, DUT.shreg);
    $dumpvars(1, DUT.bit_cnt);
    $dumpvars(1, DUT.state);
    $dumpvars(1, DUT.scl_r);
    $dumpvars(1, DUT.sda_en);
    $dumpvars(1, DUT.ack_err);
  end

  initial begin
    clk=0;
    forever #20 clk=~clk;
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      slave_bit_cnt <= 3'd7;
    end
    else begin
      if (DUT.clk_cnt == 2 && DUT.scl_r == 0) begin
        if (DUT.state == DUT.DATA && rw)
          slave_bit_cnt <= (slave_bit_cnt > 0) ? slave_bit_cnt - 1 : 3'd7;
        else if (DUT.state != DUT.DATA)
          slave_bit_cnt <= 3'd7;
      end
    end
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      slave_sda_drive <= 1'b0;
    end
    else begin
      if (DUT.clk_cnt == 1 && DUT.scl_r == 0) begin
        case (DUT.state)

          DUT.ACK:
            slave_sda_drive <= 1'b1;

          DUT.ACK2:
            slave_sda_drive <= rw ? 1'b0 : 1'b1;

          DUT.DATA:
            if (rw)
              slave_sda_drive <= ~slave_data[slave_bit_cnt];
            else
              slave_sda_drive <= 1'b0;

          default:
            slave_sda_drive <= 1'b0;
        endcase
      end
    end
  end

  assign sda = slave_sda_drive ? 1'b0 : 1'bz;

  initial begin
    reset=1;
    in=0;
    rw=0;
    din=8'b01010100;
    add=7'b0101010;
    slave_data=8'b01010100;

    #80 reset=0;

    // WRITE
    #20 in=1;
    #40 in=0;
    #7000;

    // READ
    rw=1;
    in=1;
    #40 in=0;
    #8000;

    $finish;
  end

  always @(posedge DUT.scl_r or negedge DUT.scl_r)
    $display("TIME=%0t SCL=%b SDA=%b STATE=%0d BIT=%0d SHREG=%b ACK_ERR=%b DOUT=%b",
      $time, scl, sda, DUT.state, DUT.bit_cnt, DUT.shreg, DUT.ack_err, dout);

  always @(DUT.state)
    $display("** STATE->%0d at TIME=%0t SDA=%b SCL=%b DOUT=%b",
      DUT.state, $time, sda, scl, dout);

endmodule