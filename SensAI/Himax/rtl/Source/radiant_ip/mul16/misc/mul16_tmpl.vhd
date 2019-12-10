component mul16 is
    port(rst_i: in std_logic;
         clk_en_i: in std_logic;
         result_o: out std_logic_vector(31 downto 0);
         data_a_i: in std_logic_vector(15 downto 0);
         data_b_i: in std_logic_vector(15 downto 0);
         clk_i: in std_logic);
end component;

__: mul16 port map(rst_i=> , clk_en_i=> , result_o=> , data_a_i=> , data_b_i=>
    , clk_i=> );