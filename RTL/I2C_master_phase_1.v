module i2c(
  input            clk,
  input            reset,
  input            in,
  input            rw,
  input      [7:0] din,
  input      [6:0] add,
  output reg [7:0] dout,
  inout            sda,
  output           scl);

  parameter DIVIDER = 2'd3;           
  
  localparam IDLE  = 3'd0, START = 3'd1, ADDR = 3'd2,
             ACK   = 3'd3, DATA  = 3'd4, ACK2 = 3'd5, STOP = 3'd6;
 
  reg [2:0] state;
  reg [1:0] clk_cnt;     
  reg [3:0] bit_cnt;
  reg [7:0] shreg;
  reg       scl_r;
  
  reg       sda_en;      
  reg       ack_err;
  reg       ack_hi;  
  reg [1:0] start_cnt;
  reg [1:0] stop_cnt;    

  
  wire busy = (state==ADDR) || (state==ACK)  || (state==DATA) ||
              (state==ACK2) || (state==STOP);  

  assign scl = busy ? scl_r : 1'b1;
  assign sda = sda_en ? 1'b0 : 1'bz;
  
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state     <= IDLE; 
      clk_cnt   <= 0; 
      scl_r     <= 1'b1;
      sda_en    <= 0;    
      ack_err   <= 0; 
      ack_hi    <= 0; 
      dout      <= 0;
      start_cnt <= 0;
      stop_cnt  <= 0;    
      shreg     <= 0;
      bit_cnt   <= 0;
    end
    else begin

      
      if (busy) begin
        if (clk_cnt == DIVIDER) begin 
          clk_cnt <= 0;
          if (state != STOP)
            scl_r <= ~scl_r;
          else
            scl_r <= 1'b1;           
        end
        else                         
          clk_cnt <= clk_cnt + 1;
      end
      else begin
        clk_cnt <= 0; 
        scl_r   <= 1'b1; 
      end

      
      if (state==ACK || state==ACK2)
        ack_hi <= ack_hi | scl_r;
      else                         
        ack_hi <= 0;
      
      if ((state==ACK || state==ACK2) && scl_r) 
        ack_err <= sda;
      
      
      if (busy && clk_cnt==1 && scl_r==0) begin
        case (state)
          ADDR, DATA: begin
            sda_en <= (state==DATA && rw) ? 1'b0 : ~shreg[7];
            shreg  <= (state==DATA && rw) ? {shreg[6:0], sda} : (shreg << 1);
            if (bit_cnt > 0) 
              bit_cnt <= bit_cnt - 1;
          end
           ACK,ACK2: sda_en <= 0;
          
        endcase
      end
      
      
      case (state)

        IDLE: begin 
          sda_en    <= 0; 
          start_cnt <= 0;
          stop_cnt  <= 0;
          if (in) state <= START; 
        end

        START: begin
          sda_en <= 1'b1;
          scl_r  <= 1'b1;
          if (start_cnt == 2'd2) begin
            start_cnt <= 0;
            shreg     <= {add, rw};
            bit_cnt   <= 4'd8;
            scl_r     <= 1'b0;
            state     <= ADDR;
          end
          else
            start_cnt <= start_cnt + 1;
        end

        ADDR: if (bit_cnt==0 && scl_r==1 && clk_cnt==DIVIDER)
                state <= ACK;
        
        ACK: if (ack_hi && scl_r==0) begin
               if (ack_err) state <= STOP;
               else begin
                 shreg   <= (rw ? 8'd0 : din);
                 bit_cnt <= 4'd8;
                 state   <= DATA; 
               end
             end
        
        DATA: if (bit_cnt==0 && scl_r==1 && clk_cnt==DIVIDER) begin
                dout  <= rw ? {shreg[6:0], sda} : din; 
                state <= ACK2;
              end

        ACK2: if (ack_hi && scl_r==0) begin
          sda_en   <= 1'b1;   
                stop_cnt <= 0;
                state    <= STOP;
              end
        
        STOP: begin
          scl_r <= 1'b1;
          case (stop_cnt)
            2'd0: begin
              sda_en   <= 1'b1;
              stop_cnt <= 2'd1;
            end
            2'd1: begin
              sda_en   <= 1'b1;
              stop_cnt <= 2'd2;
            end
            2'd2: begin
              sda_en   <= 1'b0;
              stop_cnt <= 2'd3;
            end
            2'd3: begin
              state    <= IDLE;
              stop_cnt <= 0;
            end
          endcase
        end

      endcase
    end
  end
endmodule
