`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/28/2023 10:50:34 PM
// Design Name: 
// Module Name: tb_eeprom_driv
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


module tb_eeprom_driv#(
    //mode
    parameter MD_SIM_ABLE = 0,
    parameter MD_ADR_AAA = 3'b0, //hard signal connect
    //number
    parameter NB_BYTE_WR = 8, //page write byte
    parameter NB_CYC_SCL = 1000, //cyc, 100M -> 10us -> 100k or 400k
    //width
    parameter WD_BYTE     = 8, //width of byte
    parameter WD_MODE_IIC = 4, //mode of iic to rom
    parameter WD_SHK_DAT = 32, //shake data
    parameter WD_SHK_ADR = 32, //shake addr
    parameter WD_ERR_INFO = 4
    
    )(

    );
    
// =============================================================
// BUS and SIP to generate signals
//sim proc
initial #100000 $stop();
//clock
reg    i_sys_clk   = 0;
reg    i_sys_rst_n = 0;
always #5 i_sys_clk = ~i_sys_clk;
initial #100 i_sys_rst_n = 1'b1;
//work mode 
reg [WD_MODE_IIC-1:0] i_par_mode_data;
always #10000 i_par_mode_data = $urandom_range(4, 0);
// --------------------------------------------------------------------
// shake driv
//shk 
reg                      s_shk_iic_valid = 0;
reg   [WD_SHK_ADR-1:0]   s_shk_iic_maddr = 0;
reg   [WD_SHK_DAT-1:0]   s_shk_iic_mdata = 0;
reg                      s_shk_iic_msync = 0;
wire                     s_shk_iic_ready;
wire   [WD_SHK_ADR-1:0]  s_shk_iic_saddr;
wire   [WD_SHK_DAT-1:0]  s_shk_iic_sdata;
wire                     s_shk_iic_ssync;
always
    begin
        #100
        s_shk_iic_valid <= 1;
        s_shk_iic_maddr <= $urandom_range(7,0);
        s_shk_iic_mdata <= $urandom_range(7,0);
        s_shk_iic_msync <= 1'b1;
        @(posedge s_shk_iic_ready)
        s_shk_iic_valid <= 0;
        s_shk_iic_msync <= 0;
        #1000;
    end
//iic
logic o_port_iic_scl  ;
logic o_port_iic_sda_o;
logic o_port_iic_sda_t;
logic i_port_iic_sda_i;
assign #5 i_port_iic_sda_i = o_port_iic_scl;
//error info
wire [WD_ERR_INFO-1:0] m_err_eeprom_info1;
// =============================================================
// module to simulate 

eeprom_driv #(
    //mode
    .MD_SIM_ABLE(MD_SIM_ABLE),
    .MD_ADR_AAA(MD_ADR_AAA), //hard signal connect
    //number
    .NB_BYTE_WR(NB_BYTE_WR), //page write byte
    .NB_CYC_SCL(NB_CYC_SCL), //cyc, 100M == 10us, support 100k or 400k
    //width
    .WD_BYTE(WD_BYTE), //width of byte
    .WD_MODE_IIC(WD_MODE_IIC), //mode of iic to rom
    .WD_SHK_DAT(WD_SHK_DAT), //shake data
    .WD_SHK_ADR(WD_SHK_ADR), //shake addr
    .WD_ERR_INFO(WD_ERR_INFO)
)u_eeprom_driv(   
    //system signals
    .i_sys_clk  (i_sys_clk  ),  
    .i_sys_rst_n(i_sys_rst_n),  
    //param of object mode
    .i_par_mode_data(i_par_mode_data),
    //SHK interface of iic
    .s_shk_iic_valid(s_shk_iic_valid),
    .s_shk_iic_maddr(s_shk_iic_maddr),
    .s_shk_iic_mdata(s_shk_iic_mdata),
    .s_shk_iic_msync(s_shk_iic_msync),
    .s_shk_iic_ready(s_shk_iic_ready),
    .s_shk_iic_saddr(s_shk_iic_saddr),
    .s_shk_iic_sdata(s_shk_iic_sdata),
    .s_shk_iic_ssync(s_shk_iic_ssync),
        
    //port of iic
    .o_port_iic_scl  (o_port_iic_scl  ),
    .o_port_iic_sda_o(o_port_iic_sda_o),
    .o_port_iic_sda_t(o_port_iic_sda_t), //1: read 0:write
    .i_port_iic_sda_i(i_port_iic_sda_i),
    //error info feedback
    .m_err_eeprom_info1(m_err_eeprom_info1)
);

// =============================================================
// assertion to monitor 
property ck_sda_o;
    @(posedge i_sys_clk) $rose(o_port_iic_scl) |-> $isunknown(o_port_iic_sda_o) == 0;
endproperty
CH_DATA: assert property(ck_sda_o)  
else     $display("data is error,o_port_iic_sda_o = %d",o_port_iic_sda_o);


endmodule


