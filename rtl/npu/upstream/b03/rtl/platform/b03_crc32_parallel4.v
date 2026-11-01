// Linear IEEE reflected CRC32 update for four little-endian bytes.
// No initial/final inversion here: caller owns the stream state.
// Explicit XOR reductions avoid a serialized 32-round combinational chain.
module b03_crc32_parallel4(input wire [31:0] seed,data,output wire [31:0] value);
    assign value[0]=^(seed&32'h04d101df) ^ ^(data&32'h04d101df);
    assign value[1]=^(seed&32'h09a203be) ^ ^(data&32'h09a203be);
    assign value[2]=^(seed&32'h1344077d) ^ ^(data&32'h1344077d);
    assign value[3]=^(seed&32'h26880efa) ^ ^(data&32'h26880efa);
    assign value[4]=^(seed&32'h4d101df4) ^ ^(data&32'h4d101df4);
    assign value[5]=^(seed&32'h9a203be9) ^ ^(data&32'h9a203be9);
    assign value[6]=^(seed&32'h3091760d) ^ ^(data&32'h3091760d);
    assign value[7]=^(seed&32'h6122ec1a) ^ ^(data&32'h6122ec1a);
    assign value[8]=^(seed&32'hc245d835) ^ ^(data&32'hc245d835);
    assign value[9]=^(seed&32'h805ab1b5) ^ ^(data&32'h805ab1b5);
    assign value[10]=^(seed&32'h046462b5) ^ ^(data&32'h046462b5);
    assign value[11]=^(seed&32'h08c8c56a) ^ ^(data&32'h08c8c56a);
    assign value[12]=^(seed&32'h11918ad4) ^ ^(data&32'h11918ad4);
    assign value[13]=^(seed&32'h232315a9) ^ ^(data&32'h232315a9);
    assign value[14]=^(seed&32'h46462b53) ^ ^(data&32'h46462b53);
    assign value[15]=^(seed&32'h8c8c56a6) ^ ^(data&32'h8c8c56a6);
    assign value[16]=^(seed&32'h1dc9ac92) ^ ^(data&32'h1dc9ac92);
    assign value[17]=^(seed&32'h3b935924) ^ ^(data&32'h3b935924);
    assign value[18]=^(seed&32'h7726b249) ^ ^(data&32'h7726b249);
    assign value[19]=^(seed&32'hee4d6493) ^ ^(data&32'hee4d6493);
    assign value[20]=^(seed&32'hd84bc8f9) ^ ^(data&32'hd84bc8f9);
    assign value[21]=^(seed&32'hb446902d) ^ ^(data&32'hb446902d);
    assign value[22]=^(seed&32'h6c5c2184) ^ ^(data&32'h6c5c2184);
    assign value[23]=^(seed&32'hd8b84309) ^ ^(data&32'hd8b84309);
    assign value[24]=^(seed&32'hb5a187cc) ^ ^(data&32'hb5a187cc);
    assign value[25]=^(seed&32'h6f920e46) ^ ^(data&32'h6f920e46);
    assign value[26]=^(seed&32'hdf241c8c) ^ ^(data&32'hdf241c8c);
    assign value[27]=^(seed&32'hba9938c7) ^ ^(data&32'hba9938c7);
    assign value[28]=^(seed&32'h71e37051) ^ ^(data&32'h71e37051);
    assign value[29]=^(seed&32'he3c6e0a3) ^ ^(data&32'he3c6e0a3);
    assign value[30]=^(seed&32'hc35cc098) ^ ^(data&32'hc35cc098);
    assign value[31]=^(seed&32'h826880ef) ^ ^(data&32'h826880ef);
endmodule
