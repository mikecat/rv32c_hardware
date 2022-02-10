TARGET=compiled.out
SOURCE=cpu.v runner.v

.PHONY: simulate
simulate: $(TARGET)
	vvp $^

.PHONY: test
test: $(TARGET)
	python ../tests/test_runner.py $(TARGET) 5

$(TARGET): $(SOURCE)
	iverilog -o $@ $^
