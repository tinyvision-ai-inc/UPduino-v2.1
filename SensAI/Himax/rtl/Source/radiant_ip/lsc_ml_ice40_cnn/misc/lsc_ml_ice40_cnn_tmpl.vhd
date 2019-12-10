component lsc_ml_ice40_cnn is
    port(
        clk: in std_logic;
        resetn: in std_logic;
        o_rd_rdy: out std_logic;
        i_start: in std_logic;
        i_we: in std_logic;
        i_waddr: in std_logic_vector(15 downto 0);
        i_din: in std_logic_vector(15 downto 0);
        o_we: out std_logic;
        o_dout: out std_logic_vector(15 downto 0);
        o_cycles: out std_logic_vector(31 downto 0);
        o_commands: out std_logic_vector(31 downto 0);
        o_fc_cycles: out std_logic_vector(31 downto 0);
        i_debug_rdy: in std_logic;
        o_debug_vld: out std_logic;
        o_fill: out std_logic;
        i_fifo_empty: in std_logic;
        i_fifo_low: in std_logic;
        o_fifo_rd: out std_logic;
        i_fifo_dout: in std_logic_vector(31 downto 0);
        o_status: out std_logic_vector(7 downto 0);
    );
end component;

__: lsc_ml_ice40_cnn port map(
    clk=>,
    resetn=>,
    o_rd_rdy=>,
    i_start=>,
    i_we=>,
    i_waddr=>,
    i_din=>,
    o_we=>,
    o_dout=>,
    o_cycles=>,
    o_commands=>,
    o_fc_cycles=>,
    i_debug_rdy=>,
    o_debug_vld=>,
    o_fill=>,
    i_fifo_empty=>,
    i_fifo_low=>,
    o_fifo_rd=>,
    i_fifo_dout=>,
    o_status=>
);
