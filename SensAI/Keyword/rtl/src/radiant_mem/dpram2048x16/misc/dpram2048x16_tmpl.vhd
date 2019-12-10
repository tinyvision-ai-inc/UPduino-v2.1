component dpram2048x16 is
    port(rd_addr_i: in std_logic_vector(10 downto 0);
         wr_clk_i: in std_logic;
         wr_clk_en_i: in std_logic;
         rd_clk_en_i: in std_logic;
         rd_en_i: in std_logic;
         rd_data_o: out std_logic_vector(15 downto 0);
         wr_data_i: in std_logic_vector(15 downto 0);
         wr_addr_i: in std_logic_vector(10 downto 0);
         wr_en_i: in std_logic;
         rd_clk_i: in std_logic);
end component;

__: dpram2048x16 port map(rd_addr_i=> , wr_clk_i=> , wr_clk_en_i=> ,
    rd_clk_en_i=> , rd_en_i=> , rd_data_o=> , wr_data_i=> , wr_addr_i=> ,
    wr_en_i=> , rd_clk_i=> );