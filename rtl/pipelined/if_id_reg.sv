



/*
.write_enable(IF_ID_Write)
.flush(IF_ID_Flush)


always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pcD    <= 32'b0;
        instrD <= 32'b0;
    end else if (flush) begin
        pcD    <= 32'b0;
        instrD <= 32'b0;   // NOP inserted
    end else if (write_enable) begin
        pcD    <= pcF;
        instrD <= instrF;
    end
    // else → stall: values remain unchanged
end

if (flush)
    instrD <= 32'b0;   // NOP

*/
