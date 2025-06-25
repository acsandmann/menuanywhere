SRCS := $(shell find src -name '*.swift')

menuanywhere: $(SRCS)
	swiftc -O -framework Cocoa -framework Carbon $(SRCS) -o menuanywhere

clean:
	rm -f menuanywhere
format:
	swiftformat src

.PHONY: clean
