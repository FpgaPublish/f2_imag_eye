`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/17/2023 09:20:00 PM
// Design Name: 
// Module Name: eeprom_driv
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//param list
`define MD_BYTE_WRITE 0
`define MD_PAGE_WRITE 1
`define MD_CADDR_READ 2
`define MD_SEQNT_READ 3


`timescale 1ns / 1ps
module eeprom_driv #(
    //mode
    parameter MD_SIM_ABLE = 0,
    parameter MD_ADR_AAA = 3'b0, //hard signal connect
    //number
    parameter NB_BYTE_WR = 8, //page write byte
    parameter NB_CYC_SCL = 1000, //100M == 10us, support 100k or 400k
    //width
    parameter WD_BYTE     = 8, //width of byte
    parameter WD_MODE_IIC = 4, //mode of iic to rom
    parameter WD_SHK_DAT = 32, //shake data
    parameter WD_SHK_ADR = 32, //shake addr
    parameter WD_ERR_INFO = 4
   )(
    //system signals
    input           i_sys_clk  ,  
    input           i_sys_rst_n,  
    //param of object mode
    input   [WD_MODE_IIC-1:0]   i_par_mode_data,
    //SHK interface of iic
    input                       s_shk_iic_valid,
    input   [WD_SHK_ADR-1:0]    s_shk_iic_maddr,
    input   [WD_SHK_DAT-1:0]    s_shk_iic_mdata,
    input                       s_shk_iic_msync,
    output                      s_shk_iic_ready,
    output  [WD_SHK_ADR-1:0]    s_shk_iic_saddr,
    output  [WD_SHK_DAT-1:0]    s_shk_iic_sdata,
    output                      s_shk_iic_ssync,
    
    //port of iic
    output          o_port_iic_scl  ,
    output          o_port_iic_sda_o,
    output          o_port_iic_sda_t, //1: read 0:write
    input           i_port_iic_sda_i,
    //error info feedback
    output   [WD_ERR_INFO-1:0]  m_err_eeprom_info1
);
//========================================================
//function to math and logic
//function y = 2 ^ N
function automatic integer EXP2_N(input integer N);
    for(EXP2_N = 1; N > 0; EXP2_N = EXP2_N * 2)
    begin
        N = N - 1;
    end
endfunction
//function y = [log2(N)]
function automatic integer LOG2_N(input integer N);
    for(LOG2_N = 0; N > 0; LOG2_N = LOG2_N + 1)
    begin
        N = N >> 1;
    end
endfunction
//========================================================
//localparam to converation and calculate
localparam WD_CYC_SCL = LOG2_N(NB_CYC_SCL); //cycle width
localparam NB_ONCE_BIT = WD_BYTE + 1; //once byte include bit
localparam NB_DEVICE_WR = {4'b1010,MD_ADR_AAA,1'b0};
localparam NB_DEVICE_RD = {4'b1010,MD_ADR_AAA,1'b1};
localparam NB_WRITE_CYCLE = 5_000_00; //5ms write idle
//========================================================
//register and wire to time sequence and combine
// shake data to write
reg [WD_SHK_ADR-1:0] r_shk_iic_maddr;
reg [WD_SHK_DAT-1:0] r_shk_iic_mdata;
// write stream
reg [WD_BYTE   -1:0] r_stm_byte_cnt;
wire                 w_byte_over_flg;
reg [WD_BYTE   -1:0] r_stm_bits_cnt;
reg [WD_CYC_SCL-1:0] r_stm_time_cnt;
//iic register
reg r_port_iic_scl  ;
reg r_port_iic_sda_o;
reg r_port_iic_sda_t;
//data fifo
reg [WD_SHK_DAT-1:0] r_shk_iic_data_fifo [0:NB_BYTE_WR-1];
reg [LOG2_N(NB_BYTE_WR)-1:0] r_data_fifo_cnt;
//write data
reg [WD_SHK_DAT-1:0] r_page_data_wr;
//read data
reg [WD_SHK_DAT-1:0] r_page_data_rd;
reg [WD_SHK_DAT-1:0] r_iic_read_data_fifo [0:NB_BYTE_WR-1];
reg [LOG2_N(NB_BYTE_WR)-1:0] r_read_fifo_cnt;
//read result
reg                    r_shk_iic_ready;
reg  [WD_SHK_ADR-1:0]  r_shk_iic_saddr;
reg  [WD_SHK_DAT-1:0]  r_shk_iic_sdata;
reg                    r_shk_iic_ssync;
reg                    r_shk_iic_ssync_d1;
//write cycle type
reg  [LOG2_N(NB_WRITE_CYCLE)-1:0] r_wait_dly_cnt;
//========================================================
//always and assign to drive logic and connect
/* @begin state machine */
//state name
localparam IDLE         = 0;
localparam START        = 1;
localparam START_FLAG   = 8;
localparam BYTE_WRITE   = 2;
localparam PAGE_WRITE   = 3;
localparam CADDR_READ   = 4;
localparam SEQNT_READ   = 6;
localparam OVERS_FLAG   = 9;
localparam OVER         = 7;   
localparam WAIT         = 10;   
//state variable
reg [3:0] cstate = IDLE;

//state logic
always @(posedge i_sys_clk)
    if(!i_sys_rst_n)
    begin
       cstate <= IDLE;
    end
    else
    begin
        case(cstate)
            IDLE : if(1) //wheter goto next state
                begin  
                    if(1) //which state to go
                    begin
                        cstate <= START;
                    end
                end
            START:if(s_shk_iic_valid)
                begin
                    if(1)
                    begin
                        cstate <= START_FLAG;
                    end
                end
            START_FLAG: if(r_stm_time_cnt >= NB_CYC_SCL - 1'b1)
                begin
                    if(i_par_mode_data == `MD_BYTE_WRITE)
                    begin
                        cstate <= BYTE_WRITE;
                    end
                    else if(i_par_mode_data == `MD_PAGE_WRITE)
                    begin
                        cstate <= PAGE_WRITE;
                    end
                    else if(i_par_mode_data == `MD_CADDR_READ)
                    begin
                        cstate <= CADDR_READ;
                    end
                    else if(i_par_mode_data == `MD_SEQNT_READ)
                    begin
                        cstate <= SEQNT_READ;
                    end
                    
                end
            BYTE_WRITE: if(r_stm_byte_cnt == 2
                        && w_byte_over_flg)
                begin
                    if(1)
                    begin
                        cstate <= OVERS_FLAG;
                    end
                end
            PAGE_WRITE: if(r_stm_byte_cnt >= r_data_fifo_cnt + 1
                        && w_byte_over_flg)
                begin
                    if(1)
                    begin
                        cstate <= OVERS_FLAG;
                    end
                end
            CADDR_READ: if(r_stm_byte_cnt == 1      
                        && w_byte_over_flg)
                begin
                    if(1)
                    begin
                        cstate <= OVERS_FLAG;
                    end
                end
            SEQNT_READ: if(r_stm_byte_cnt >= r_data_fifo_cnt 
                        && w_byte_over_flg)
                begin
                    if(1)
                    begin
                        cstate <= OVERS_FLAG;
                    end
                end
            OVERS_FLAG: if(r_stm_time_cnt >= NB_CYC_SCL - 1'b1)
                begin
                    if(1)
                    begin
                        cstate <= OVER;
                    end
                end
            OVER: if(r_shk_iic_saddr > 0) //SEQNT_READ mode 
                begin
                    if(r_read_fifo_cnt == (r_shk_iic_saddr - 1'b1))
                    begin
                        cstate <= WAIT;
                    end
                end
            else 
                begin
                    if(1)
                    begin
                        cstate <= WAIT;
                    end
                end
            WAIT: if(r_wait_dly_cnt == NB_WRITE_CYCLE - 1'b1
                ||  MD_SIM_ABLE)
                begin
                    if(1)
                    begin
                        cstate <= IDLE;
                    end
                end
            default: cstate <= IDLE;
        endcase
    end
/* @end state machine  */
//data write temp
always@(posedge i_sys_clk)
begin
    if(!i_sys_rst_n) //system reset
    begin
        r_shk_iic_maddr <= 'b0;  //
        r_shk_iic_mdata <= 'b0;
    end
    else if(cstate == START && s_shk_iic_valid) //
    begin
        r_shk_iic_maddr <= s_shk_iic_maddr;  //
        r_shk_iic_mdata <= s_shk_iic_mdata;
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_data_fifo_cnt <= 1'b0;
    end
    else if(cstate == START && s_shk_iic_valid && s_shk_iic_msync)
    begin
        r_data_fifo_cnt <= 1'b1;
    end
    else if(cstate == START_FLAG)
    begin
        if(s_shk_iic_msync)
        begin
            r_data_fifo_cnt <= (r_data_fifo_cnt < NB_BYTE_WR - 1'b1) ? r_data_fifo_cnt + 1'b1 : 
                                r_data_fifo_cnt;
        end
    end
end
integer i;
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        for(i=0;i<NB_BYTE_WR;i=i+1)
        begin:FOR_NB_BYTE_WR
            r_shk_iic_data_fifo[i] <= 1'b0;
        end
    end
    else if(cstate == START || cstate == START_FLAG)
    begin
        if(s_shk_iic_msync)
        begin
            r_shk_iic_data_fifo[r_data_fifo_cnt] <= s_shk_iic_mdata;
        end
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_page_data_wr <= 1'b0;
    end
    else if(cstate == PAGE_WRITE)
    begin
        if(r_stm_byte_cnt > 1 && r_stm_byte_cnt <= NB_BYTE_WR + 1)
        begin
            r_page_data_wr <= r_shk_iic_data_fifo[r_stm_byte_cnt-2];
        end
    end
end
//data write counter
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_stm_time_cnt <= 'b0;
    end
    else if(cstate == START_FLAG
        ||  cstate == OVERS_FLAG
        ||  cstate == BYTE_WRITE
        ||  cstate == PAGE_WRITE
        ||  cstate == CADDR_READ
        ||  cstate == SEQNT_READ)
    begin
        if(r_stm_time_cnt >= NB_CYC_SCL - 1'b1)
        begin
            r_stm_time_cnt <= 1'b0;
        end
        else 
        begin
            r_stm_time_cnt <= r_stm_time_cnt + 1'b1;
        end
    end 
    
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_stm_bits_cnt <= 'b0;
    end
    else if(cstate == BYTE_WRITE
        ||  cstate == PAGE_WRITE
        ||  cstate == CADDR_READ
        ||  cstate == SEQNT_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL - 1'b1)
        begin
            if(r_stm_bits_cnt == NB_ONCE_BIT - 1'b1)
            begin
                r_stm_bits_cnt <= 1'b0;
            end
            else 
            begin
                r_stm_bits_cnt <= r_stm_bits_cnt + 1'b1;
            end
        end
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_stm_byte_cnt <= 1'b0;
    end
    else if(cstate == BYTE_WRITE
        ||  cstate == PAGE_WRITE
        ||  cstate == CADDR_READ
        ||  cstate == SEQNT_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL - 1'b1
        && r_stm_bits_cnt == NB_ONCE_BIT - 1'b1)
        begin
            r_stm_byte_cnt <= r_stm_byte_cnt + 1'b1;
        end
    end
end
assign w_byte_over_flg =    r_stm_time_cnt == NB_CYC_SCL - 1'b1
                        &&  r_stm_bits_cnt == NB_ONCE_BIT - 1'b1;
//operate write
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_port_iic_scl <= 1'b1;
    end
    else if(cstate == START_FLAG)
    begin
        r_port_iic_scl <= 1'b1;
    end
    else if(cstate == BYTE_WRITE || cstate == PAGE_WRITE
        ||  cstate == CADDR_READ || cstate == SEQNT_READ
        ||  cstate == OVERS_FLAG)
    begin
        if(r_stm_time_cnt == 1'b0)
        begin
            r_port_iic_scl <= 1'b0;
        end
        else if(r_stm_time_cnt == NB_CYC_SCL / 2 - 1)
        begin
            r_port_iic_scl <= 1'b1;
        end
    end
end
// ----------------------------------------------------------
// data write

always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_port_iic_sda_o <= 1'b1;
        r_port_iic_sda_t <= 1'b0;
    end
    else if(cstate == START_FLAG)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 2 - 1)
        begin
            r_port_iic_sda_o <= 1'b0;
            r_port_iic_sda_t <= 1'b0;
        end
    end
    else if(cstate == OVERS_FLAG)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 4 - 1)
        begin
            r_port_iic_sda_o <= 1'b0;
            r_port_iic_sda_t <= 1'b0;
        end
        else if(r_stm_time_cnt == NB_CYC_SCL * 3 / 4 - 1)
        begin
            r_port_iic_sda_o <= 1'b1;
            r_port_iic_sda_t <= 1'b0;
        end
    end
    else if(cstate == BYTE_WRITE)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 4 - 1)
        begin
            if(r_stm_byte_cnt == 0) //first device addr count
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= NB_DEVICE_WR[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt == 1)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= r_shk_iic_maddr[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt == 2)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= r_shk_iic_mdata[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
        end
    end
    else if(cstate == PAGE_WRITE)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 4 - 1)
        begin
            if(r_stm_byte_cnt == 0) //first device addr count
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= NB_DEVICE_WR[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt == 1)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= r_shk_iic_maddr[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt >= 2)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= r_page_data_wr[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
        end
    end
    else if(cstate == CADDR_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 4 - 1)
        begin
            if(r_stm_byte_cnt == 0) //first device addr count
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= NB_DEVICE_RD[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt == 1)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= 1'b0; //read data
                    r_port_iic_sda_t <= 1'b1;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b1; //write ack
                    r_port_iic_sda_t <= 1'b0;
                end
            end
        end
    end
    else if(cstate == SEQNT_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL / 4 - 1)
        begin
            if(r_stm_byte_cnt == 0) //first device addr count
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= NB_DEVICE_RD[WD_BYTE - 1 - r_stm_bits_cnt];
                    r_port_iic_sda_t <= 1'b0;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //read ack
                    r_port_iic_sda_t <= 1'b1;
                end
            end
            else if(r_stm_byte_cnt >= 1)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_port_iic_sda_o <= 1'b0; //
                    r_port_iic_sda_t <= 1'b1;
                end
                else
                begin
                    r_port_iic_sda_o <= 1'b0; //write ack
                    r_port_iic_sda_t <= 1'b0;
                end
            end
        end
    end
end
assign o_port_iic_scl   = r_port_iic_scl  ;
assign o_port_iic_sda_o = r_port_iic_sda_o;
assign o_port_iic_sda_t = r_port_iic_sda_t;
// ----------------------------------------------------------
// data read
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_page_data_rd <= 1'b0;
    end
    else if(cstate == SEQNT_READ || cstate == CADDR_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL * 3 / 4 - 1)
        begin
            if(r_stm_byte_cnt >= 1)
            begin
                if(r_stm_bits_cnt < WD_BYTE)
                begin
                    r_page_data_rd[WD_BYTE - 1 - r_stm_bits_cnt] <= i_port_iic_sda_i;
                end
            end
        end
    end
end
integer j;
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        for(j = 0; j < NB_BYTE_WR; j = j + 1)
        begin:FOR2_NB_BYTE_WR
            r_iic_read_data_fifo[j] <= 1'b0;
        end
    end
    else if(cstate === CADDR_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL * 3 / 4 - 1)
        begin
            if(r_stm_byte_cnt == 1)
            begin
                if(r_stm_bits_cnt == WD_BYTE)
                begin
                    r_iic_read_data_fifo[0] <= r_page_data_rd;
                end
            end
        end
    end
    else if(cstate == SEQNT_READ)
    begin
        if(r_stm_time_cnt == NB_CYC_SCL * 3 / 4 - 1)
        begin
            if(r_stm_byte_cnt >= 1 && r_stm_byte_cnt <= r_data_fifo_cnt + 1)
            begin
                if(r_stm_bits_cnt == WD_BYTE)
                begin
                    r_iic_read_data_fifo[r_stm_byte_cnt - 1] <= r_page_data_rd;
                end
            end
        end
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_read_fifo_cnt <= 1'b0;
    end
    else if(cstate == OVER)
    begin
        if(r_shk_iic_ssync)
        begin
            r_read_fifo_cnt <= (r_read_fifo_cnt < (r_shk_iic_saddr - 1'b1)) ? r_read_fifo_cnt + 1'b1 :
                                r_read_fifo_cnt;
        end
    end
end
// ----------------------------------------------------------
// read result to shake

always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_shk_iic_saddr <= 1'b0;
    end
    else if(cstate == SEQNT_READ)
    begin
        r_shk_iic_saddr <= r_data_fifo_cnt;
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_shk_iic_sdata <= 1'b0;
    end
    else if(cstate == OVER)
    begin
        r_shk_iic_sdata <= r_iic_read_data_fifo[r_read_fifo_cnt];
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_shk_iic_ssync <= 1'b0;
    end
    else if(cstate == OVER)
    begin
        if(r_read_fifo_cnt == r_shk_iic_saddr - 1'b1)
        begin
            r_shk_iic_ssync <= 1'b0;
        end
        else if(r_shk_iic_saddr > 0)
        begin
            r_shk_iic_ssync <= 1'b1;
        end
    end
end
always@(posedge i_sys_clk)
begin
    if(1) //update in one cycle
    begin
        r_shk_iic_ssync_d1 <= r_shk_iic_ssync;
    end
end
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_shk_iic_ready <= 1'b0;
    end
    else if(cstate == OVER)
    begin
        r_shk_iic_ready <= 1'b1;
    end
end
assign s_shk_iic_ready = r_shk_iic_ready;
assign s_shk_iic_saddr = r_shk_iic_saddr;
assign s_shk_iic_sdata = r_shk_iic_sdata;
assign s_shk_iic_ssync = r_shk_iic_ssync_d1;
//write over and wait idle
always@(posedge i_sys_clk)
begin
    if(cstate == IDLE) //state IDLE reset
    begin
        r_wait_dly_cnt <= 1'b0;
    end
    else if(cstate == WAIT)
    begin
        r_wait_dly_cnt <= r_wait_dly_cnt + 1'b1;
    end
end
//========================================================
//module and task to build part of system

//========================================================
//expand and plug-in part with version 

//========================================================
//ila and vio to debug and monitor




endmodule
