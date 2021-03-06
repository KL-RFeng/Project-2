----------------------------------------------------------------------------------
--
-- Author: Kurt Lehmann
--
-- Description:
-- This design is a VGA controller and implements a checkerboard display with a red square
-- that moves along the board in response to pressing the push-buttons.
----------------------------------------------------------------------------------

library IEEE; 
use IEEE.STD_LOGIC_1164.ALL; 
use IEEE.NUMERIC_STD.ALL; 


entity top_level is
    Port ( 
     -- Summary of Inputs, Outputs, and Signals:
-- Inputs 
            SW : in std_logic_vector(0 downto 0); --Switch0: Active high reset 
            BTNU : in STD_LOGIC; -- Move the red square up one position per button press
            BTND : in STD_LOGIC; -- Move the red square down one position per button press
            BTNL : in STD_LOGIC; -- Move the red square left one position per button press
            BTNR : in STD_LOGIC; -- Move the red square right one position per button press            
            CLK100MHZ : in STD_LOGIC; -- System Clock, 100MHz
-- Outputs 
           VGA_R, VGA_B, VGA_G : out std_logic_vector(3 downto 0);  -- Red, Green, Blue color signals, each 
           VGA_HS, VGA_VS : out std_logic; -- Horizontal and Vertical sync pulse, each 1-bit wide
           SEG7_CATH : out std_logic_vector(7 downto 0); -- Cathode signals, 8-bits wide
           AN : out std_logic_vector(7 downto 0); -- --Anode signals, 8-bits wide.  AN is anodeSelect 
           LED : out std_logic_vector(0 downto 0)
           );
end top_level;


architecture Behavioral of top_level is
    signal reset : std_logic;
    signal en25 : std_logic; 
    signal pulseCnt : unsigned(1 downto 0);  
    constant maxCount : unsigned(1 downto 0) := "11";  --Binary value for 3  2 bits
    signal horz_cntr: unsigned(9 downto 0); 
    signal vsenable: std_logic; --Enable for the Vertical counter
    constant hpixels : unsigned (9 downto 0) := to_unsigned (800,10);--"1100100000"; --decimal 800 has 10 binary digits
    signal vert_cntr : unsigned(9 downto 0); -- Vertical counter
    constant vlines : unsigned (9 downto 0) := to_unsigned (521,10);--"1000001001"; --decimal 521 has 10 binary digits
    signal display_sig : std_logic;
    signal red_sig, green_sig, blue_sig : std_logic_vector(3 downto 0);

    constant widthRedSq : integer := 32;  -- Width of the red square
    constant heightRedSq : integer := 32; -- Height of the red square
    -- Signals C1 and R1 keep track of the current column and row of the upper LH position of the red square.
    signal col, row : unsigned (9 downto 0); 
    signal display_RedSq, R, G, B: std_logic;
    constant numberColumns : integer := 20;  -- total number of columns  
    signal columnPbCntr : unsigned(4 downto 0); -- column counter
    signal columnPushbtnCntr : std_logic_vector(4 downto 0);
    constant numberRows : integer := 15; -- total number of rows   
    signal rowPbCntr : unsigned(4 downto 0); -- row counter
    signal rowPushbtnCntr : std_logic_vector(4 downto 0);   
    signal BTNR_last : STD_LOGIC;
    signal BTNL_last : STD_LOGIC;  
    signal debouncedBTNU_last : STD_LOGIC;
    signal debouncedBTND_last : STD_LOGIC;
    signal debouncedBTNL_last : STD_LOGIC;
    signal debouncedBTNR_last : STD_LOGIC;  

   constant debounceMaxCnt : integer := 10000000; -- - (1/100,000,000 Hz clock)(10,000,000) = 0.1 s or 100 ms but clock 2x rate so doubled since not specifying rising edge 
--  constant debounceMaxCnt : integer :=   100000; -- - (1/100,000,000 Hz clock)(100,000) =  1 ms for test for shorter sim time.  
 
    signal debounceCntrU : unsigned(23 downto 0); -- 2^24 = 16,777,216 which is > 10,000,000  verified (23 downto 0) works and don't need larger value
    signal debounceCntrD : unsigned(23 downto 0); -- 2^24 = 16,777,216 which is > 10,000,000
    signal debounceCntrL : unsigned(23 downto 0); -- 2^24 = 16,777,216 which is > 10,000,000
    signal debounceCntrR : unsigned(23 downto 0); -- 2^24 = 16,777,216 which is > 10,000,000
    signal debouncedBTNU : std_logic; 
    signal debouncedBTND : std_logic;
    signal debouncedBTNL : std_logic;
    signal debouncedBTNR : std_logic;
    
    signal clear : std_logic; 
    signal pulseCnt1KHz : unsigned(16 downto 0); --17 bits
    constant maxCount1KHz : unsigned(16 downto 0) := to_unsigned(100000, 17); 
    signal cntr3bit : unsigned(2 downto 0); 
    signal setAnode : std_logic_vector(7 downto 0);
    signal selChar : std_logic_vector(3 downto 0);
    signal seg7 : std_logic_vector (7 downto 0);   

    signal char0 : STD_LOGIC_VECTOR (3 downto 0);    
    signal char2 : STD_LOGIC_VECTOR (3 downto 0);
    signal char3 : STD_LOGIC_VECTOR (0 downto 0);
    signal char3Concatenate : STD_LOGIC_VECTOR (3 downto 0);





begin
reset <= SW(0);
LED(0) <= SW(0);

--LED_0 <= switch0;
    -- 25MHz Pulse Generator 
    process(CLK100MHZ, reset) 
    begin 
        if(reset = '1') then 
            pulseCnt <= (others=>'0'); 
    elsif(rising_edge(CLK100MHZ)) then 
        if (en25 = '1') then 
            pulseCnt <= (others=>'0'); 
        else 
             pulseCnt <= pulseCnt + 1; -- upcounter
        end if; 
    end if; 
end process; 
--pulseCnttest <= std_logic_vector(pulseCnt); 
en25 <= '1' when (pulseCnt = maxCount) else '0'; 
--pulse_25MHz <= en25; 

 --Counter for the horizontal sync signal VGA_HS
    process(CLK100MHZ, reset)
    begin
      if(reset = '1') then
          horz_cntr <= (others=>'0'); 
      elsif (rising_edge(CLK100MHZ)) then
        if horz_cntr = hpixels - 1 then  --The horizontal counter has reached the end of pixel count from 0 to 799
          horz_cntr <= (others => '0');   --reset the counter
          vsenable <= '1'; --Enable the vertical counter
       elsif (en25 = '1') then 
          horz_cntr <= horz_cntr + 1; --Increment the horizontal counter
          vsenable <= '0';  --Leave the vsenable off
       end if;
    end if;
end process;
--horizontal_counter <= std_logic_vector(horz_cntr);
--vsenableTest <= vsenable;
VGA_HS <= '0' when (horz_cntr >=656 and horz_cntr < 752) else '1'; --Horizontal Sync Pulse is '0' between [656,752) otherwise '1'.

--Counter for the vertical sync siglal VGA_VSV
process(CLK100MHZ, reset)
begin
       if(reset = '1') then
          vert_cntr <= (others=>'0');
       elsif (rising_edge(CLK100MHZ) and vsenable = '1') then  -- Increment when enabled
          if vert_cntr = vlines - 1 then  --The vertical counter has reached the end of pixel count from 0 to 520
             vert_cntr <= (others => '0');   --reset the counter
          elsif (en25 = '1') then 
             vert_cntr <= vert_cntr  + 1 ; -- Increment vertical upcounter
       end if;
    end if;
end process;
--vertical_counter <= std_logic_vector(vert_cntr);
VGA_VS <= '0' when (vert_cntr >= 490 and vert_cntr < 492) else '1'; --Vertical Sync Pulse is '0' between [490,492) otherwise '1'.
 
--Enable video out when within the porches
display_sig <= '1' when (((horz_cntr >= 0) and (horz_cntr < 640)) 
                   and (vert_cntr >= 0) and (vert_cntr < 480)) 
                   else '0';
--display <= display_sig;

process (CLK100MHZ, reset) is 
  begin
---- BTNU Switch Debouncer
    if(reset = '1') then 
      debounceCntrU <= (others => '0');
  elsif (rising_edge(CLK100MHZ)) then
    if (BTNU = '1')  then
      if (debounceCntrU < debounceMaxCnt) then 
        debounceCntrU <= debounceCntrU + 1;   --Increment the counter if end of counter is not reached
	  else 
        debouncedBTNU <= '1'; -- If the end of the counter is reached at 100ms, set debouncedSwitch set to 1
      end if;
    else -- Whenever the switch goes to '0' it will reset the counter back to zero and clear the debounced output.
      debounceCntrU <= (others => '0');  -- this statement making BTNU not to work
      debouncedBTNU <= '0';
    end if;  
 end if;
 
---- BTND Switch Debouncer
    if(reset = '1') then 
      debounceCntrD <= (others => '0');
  elsif (rising_edge(CLK100MHZ)) then
    if (BTND = '1')  then
      if (debounceCntrD < debounceMaxCnt) then 
        debounceCntrD <= debounceCntrD + 1;   --Increment the counter if end of counter is not reached
	  else 
        debouncedBTND <= '1'; -- If the end of the counter is reached at 100ms, set debouncedSwitch set to 1
      end if;
    else -- Whenever the switch goes to '0' it will reset the counter back to zero and clear the debounced output.
      debounceCntrD <= (others => '0');  -- this statement making BTNU not to work
      debouncedBTND <= '0';
    end if;
 end if;

 ---- BTNR Switch Debouncer
    if(reset = '1') then 
      debounceCntrR <= (others => '0');  
  elsif (rising_edge(CLK100MHZ)) then
    if (BTNR = '1')  then
      if (debounceCntrR < debounceMaxCnt) then 
        debounceCntrR <= debounceCntrR + 1;   --Increment the counter if end of counter is not reached
	  else 
        debouncedBTNR <= '1'; -- If the end of the counter is reached at 100ms, set debouncedSwitch set to 1
      end if;
    else -- Whenever the switch goes to '0' it will reset the counter back to zero and clear the debounced output.
      debounceCntrR <= (others => '0');  -- this statement making BTNU not to work
      debouncedBTNR <= '0';
   end if;
 end if;

   ---- BTNL Switch Debouncer
    if(reset = '1') then
      debounceCntrL <= (others => '0');    
   elsif (rising_edge(CLK100MHZ)) then
     if (BTNL = '1')  then
      if (debounceCntrL < debounceMaxCnt) then 
        debounceCntrL <= debounceCntrL + 1;   --Increment the counter if end of counter is not reached
	  else 
        debouncedBTNL <= '1'; -- If the end of the counter is reached at 100ms, set debouncedSwitch set to 1
      end if;
    else -- Whenever the switch goes to '0' it will reset the counter back to zero and clear the debounced output.
      debounceCntrL <= (others => '0');  -- this statement making BTNU not to work
       debouncedBTNL <= '0';
   end if;
 end if;
 end process; 

--store the last debounced values of BTNR, BTNL, BTNU, BTND (used to flag rising edge later)
process(CLK100MHZ, reset)
begin
    if(reset = '1') then
        debouncedBTNR_last <= '0';
    elsif(rising_edge(CLK100MHZ)) then
        debouncedBTNR_last <= debouncedBTNR; -- store last used version
    end if;
--store the last value of BTNL (used to flag rising edge later)
    if(reset = '1') then
        debouncedBTNL_last <= '0';
    elsif(rising_edge(CLK100MHZ)) then
        debouncedBTNL_last <= debouncedBTNL; -- store last used version
    end if;
----store the last value of BTNU (used to flag rising edge later)
    if(reset = '1') then
        debouncedBTNU_last <= '0';
    elsif(rising_edge(CLK100MHZ)) then
        debouncedBTNU_last <= debouncedBTNU; -- store last used version
    end if;
--store the last value of BTND (used to flag rising edge later)
    if(reset = '1') then
        debouncedBTND_last <= '0';
    elsif(rising_edge(CLK100MHZ)) then
        debouncedBTND_last <= debouncedBTND; -- store last used version
    end if;
end process;

--Counters for the column BTNR and BTNL pushbutton on the rising edge to move red square right or left
 process(CLK100MHZ, reset)
    begin
      if(reset = '1') then
          columnPbCntr <= (others=>'0'); 
      elsif (rising_edge(CLK100MHZ)) then  -- on the rising edge
        if (debouncedBTNR_last = '0' and debouncedBTNR = '1') then
     -- If the column counter has incremented one column beyond the rightmost square in a row, then it resets to    
     -- the leftmost column
        if columnPbCntr = numberColumns - 1 then  
          columnPbCntr <= (others => '0');   --reset the column counter to leftmost column square
        else 
          columnPbCntr <= columnPbCntr + 1; --Increment the horizontal counter
       end if;
    end if;
  end if;
--Counter for the column BTNL pushbutton on the rising edge
      if(reset = '1') then
          columnPbCntr <= (others=>'0');
      elsif (rising_edge(CLK100MHZ)) then  -- on the rising edge
       if (debouncedBTNL_last = '0' and debouncedBTNL = '1') then 
     -- If the column counter has incremented one column beyond the rightmost square in a row, 
     -- then it resets to the leftmost column
        if columnPbCntr = 0 then  -- if reached column and needs to wraparound to the rightmost position
          columnPbCntr <= "10011"; --reset the column counter to rightmost column square which is "1001100000"; = 20th col 13 Hex
       else 
          columnPbCntr <= columnPbCntr - 1; --Decrement the column counter
       end if;
    end if;
  end if;    
end process;

columnPushbtnCntr <= std_logic_vector(columnPbCntr);
--colPushbtnCntrOut <= columnPushbtnCntr;

--Counter for the row BTND and BTNU pushbutton on the rising edge to move red square down or up
 process(CLK100MHZ, reset)
    begin
      if(reset = '1') then
          rowPbCntr <= (others=>'0'); 
      elsif (rising_edge(CLK100MHZ))then -- on the rising edge
       if (debouncedBTND_last = '0' and debouncedBTND = '1') then 
  -- If the row counter has incremented one row beyond the rightmost square in a row, then it resets to    
  -- the leftmost row
        if rowPbCntr = numberrows - 1 then  
          rowPbCntr <= (others => '0');   --reset the row counter to uppermost row square
       else 
          rowPbCntr <= rowPbCntr + 1; --Increment the row counter
       end if;
    end if;
  end if;    
-- Counter for the row BTNU pushbutton on the rising edge
      if(reset = '1') then
          rowPbCntr <= (others=>'0'); 
      elsif (rising_edge(CLK100MHZ))then -- on the rising edge
       if (debouncedBTNU_last = '0' and debouncedBTNU = '1') then  -- on the rising edge
     -- If the row counter has incremented one rown beyond the rightmost square in a row, 
     -- then it resets to the leftmost row
        if rowPbCntr = 0 then  -- if reached row and needs to wraparound to the rightmost position
          rowPbCntr <= "01110"; --reset the row counter to lowermost row square which is "0111000000"; = 15th row 0E Hex
       else 
          rowPbCntr <= rowPbCntr - 1; --Decrement the horizontal counter
       end if;
    end if;
  end if;  
end process;

rowPushbtnCntr <= std_logic_vector(rowPbCntr);
--rowPushbtnCntrOut <= rowPushbtnCntr;

-- Location red square based on
col <=  columnPbCntr & "00000";  -- affects horizontal location of square
row <= rowPbCntr & "00000";  -- affects vertical location of square

-- Enable red square within these boundaries
display_RedSq <= '1' when (((horz_cntr >= 0 + col) and (horz_cntr < 0 + col + widthRedSq)) 
                     and (vert_cntr >= 0 + row) and (vert_cntr < 0 + row + heightRedSq)) 
                     else '0';

process(display_sig, vert_cntr, horz_cntr)
begin
    red_sig <= (others=>'0');  -- Intialize values to "0000";
    green_sig <= (others=>'0'); -- Intialize values to "0000";
    blue_sig <= (others=>'0'); -- Intialize values to "0000";
    if(display_sig = '1' and display_RedSq = '1') then
      red_sig <= (others=>'1'); -- Draw red square
 --Create checkerboard display wherever no red square is present    
      elsif(display_sig = '1') then
      blue_sig <= (horz_cntr(5) & horz_cntr(5) & horz_cntr(5) & horz_cntr(5)) xor (vert_cntr(5) & vert_cntr(5) & vert_cntr(5) & vert_cntr(5));     
      green_sig <= not ((horz_cntr(5) & horz_cntr(5) & horz_cntr(5) & horz_cntr(5)) xor (vert_cntr(5) & vert_cntr(5) & vert_cntr(5) & vert_cntr(5)));
    end if;
end process;
VGA_R <= red_sig;
VGA_G <= green_sig;
VGA_B <= blue_sig;

 -- 1 kHz Pulse Generator 
    process(CLK100MHZ, reset) 
    begin 
        if(reset = '1') then 
            pulseCnt1KHz <= (others=>'0'); 
    elsif(rising_edge(CLK100MHZ)) then 
        if (clear = '1') then 
            pulseCnt1KHz <= (others=>'0'); 
        else 
             pulseCnt1KHz <= pulseCnt1KHz + 1; -- upcounter
        end if; 
    end if; 
end process; 
--pulseCnttest <= pulseCnt; 
clear <= '1' when (pulseCnt1KHz = maxCount1KHz) else '0'; 
--pulseOut1KHz <= clear; 

-- Anode 3-bit Counter   
process(CLK100MHZ, reset) 
begin
   if(reset = '1') then 
     cntr3bit <= (others => '0'); 
   elsif(rising_edge(CLK100MHZ)) then 
      if(clear = '1') then
   	    cntr3bit <= cntr3bit + 1; 
   	  end if; 
   end if; 
--anodeCntOut <= std_logic_vector(cntr3bit);   
end process;

-- 3 to 8 Anode Decoder Active Low
process(CLK100MHZ, reset) 
begin
   if(reset = '1') then 
     setAnode <= (others => '0'); 
   elsif(rising_edge(CLK100MHZ)) then 
        case cntr3bit is
            when "000" => setAnode <=  "11111110"; -- digit 1 on
            when "001" => setAnode <=  "11111101"; -- digit 2 on
            when "010" => setAnode <=  "11111011"; -- digit 3 on
            when "011" => setAnode <=  "11110111"; -- digit 4 on
            when "100" => setAnode <=  "11101111"; -- digit 5 on
            when "101" => setAnode <=  "11011111"; -- digit 6 on
            when "110" => setAnode <=  "10111111"; -- digit 7 on
            when "111" => setAnode <=  "01111111"; -- digit 8 on
            when others => setAnode <=  "11111111"; -- no digit on             
        end case;
   end if; 
AN <= std_logic_vector(setAnode);   --AN is anodeSelect
end process;

char0 <= rowPushbtnCntr(3 downto 0); -- to displays row number (y-axis)
char2 <= columnPushbtnCntr(3 downto 0); -- to displays col number for first hex digit (x-axis)
char3 <= columnPushbtnCntr(4 downto 4); -- to displays col number for second hex digit (x-axis) 
char3Concatenate <=  "000" & char3;

--char0Out <= char0;
--char2Out <= char2; 
--char3ConcatenateOut <= char3Concatenate; 

-- 8 to 1 Character Selection MUX
process(CLK100MHZ, reset) 
begin
   if(reset = '1') then 
     selChar <= (others => '0'); 
   elsif(rising_edge(CLK100MHZ)) then 
        case cntr3bit is
            when "000" => selChar <=  char0;
            when "001" => selChar <=  x"0";
            when "010" => selChar <=  char2;
            when "011" => selChar <=  char3Concatenate;
            when "100" => selChar <=  x"0";
            when "101" => selChar <=  x"0";
            when "110" => selChar <=  x"0";
            when "111" => selChar <=  x"0";
            when others => selChar <= x"0";
        end case;
   end if; 
--charSelect <=  selChar;   
end process;

-- 7-Segment Encoder
process(CLK100MHZ, reset) 
begin
   if(reset = '1') then 
     seg7 <= (others => '0'); 
   elsif(rising_edge(CLK100MHZ)) then 
        case selChar is
            when x"0" => seg7 <=  "11000000"; -- 7-SEGMENT displays 0
            when x"1" => seg7 <=  "11111001"; -- 7-SEGMENT displays 1           
            when x"2" => seg7 <=  "10100100"; -- 7-SEGMENT displays 2
            when x"3" => seg7 <=  "10110000"; -- 7-SEGMENT displays 3          
            when x"4" => seg7 <=  "10011001"; -- 7-SEGMENT displays 4
            when x"5" => seg7 <=  "10010010"; -- 7-SEGMENT displays 5            
            when x"6" => seg7 <=  "10000010"; -- 7-SEGMENT displays 6
            when x"7" => seg7 <=  "11111000"; -- 7-SEGMENT displays 7           
            when x"8" => seg7 <=  "10000000"; -- 7-SEGMENT displays 8
            when x"9" => seg7 <=  "10010000"; -- 7-SEGMENT displays 9            
            when x"A" => seg7 <=  "10001000"; -- 7-SEGMENT displays A
            when x"B" => seg7 <=  "10000011"; -- 7-SEGMENT displays B          
            when x"C" => seg7 <=  "11000110"; -- 7-SEGMENT displays C
            when x"D" => seg7 <=  "10100001"; -- 7-SEGMENT displays D           
            when x"E" => seg7 <=  "10000110"; -- 7-SEGMENT displays E
            when others => seg7 <=  "10001110"; -- 7-SEGMENT displays F            
        end case;
   end if; 
SEG7_CATH  <=  seg7;   
end process;

end Behavioral;   

