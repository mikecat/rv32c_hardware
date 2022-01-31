TARGET=compiled.out
SOURCE=cpu.v runner.v

.PHONY: simulate
simulate: $(TARGET)
	vvp $^

$(TARGET): $(SOURCE)
	iverilog -o $@ $^
