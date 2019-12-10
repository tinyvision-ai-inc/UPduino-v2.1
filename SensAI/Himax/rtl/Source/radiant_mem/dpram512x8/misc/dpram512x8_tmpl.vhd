component dpram512x8 is
    port(rd_addr_i: in std_logic_vector(8 downto 0);
         wr_clk_i: in std_logic;
         wr_clk_en_i: in std_logic;
         rd_clk_en_i: in std_logic;
         rd_en_i: in std_logic;
         rd_data_o: out std_logic_vector(7 downto 0);
         wr_data_i: in std_logic_vector(7 downto 0);
         wr_addr_i: in std_logic_vector(8 downto 0);
         wr_en_i: in std_logic;
         rd_clk_i: in std_logic);
end component;

__: dpram512x8 port map(rd_addr_i=> , wr_clk_i=> , wr_clk_en_i=> ,
    rd_clk_en_i=> , rd_en_i=> , rd_data_o=> , wr_data_i=> , wr_addr_i=> ,
    wr_en_i=> , rd_clk_i=> );