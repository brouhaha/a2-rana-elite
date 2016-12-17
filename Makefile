all: check

check: rana-31.bin
	echo "3087ad4f71d8b76add2870939552b9b369efcc0ac949a27d5e9f00162b4488dc  rana-31.bin" | sha256sum -c

%.p %.lst: %.asm
	asl -cpu 6502 -L -C $<

%.bin: %.p
	p2bin -r '$$c800-$$cfff' $< $@

clean:
	rm -f *.lst *.p *.bin
