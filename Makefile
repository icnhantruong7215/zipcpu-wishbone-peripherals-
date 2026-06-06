TOP=tb_soc_stub_top

.PHONY: sim build run wave clean

sim: build run

build:
	verilator -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-WIDTH -Wno-UNUSED -Wno-BLKSEQ \
		--binary --timing --trace -DVERILATOR --top-module $(TOP) -f filelist_verilator.f

run:
	./obj_dir/V$(TOP)

wave:
	gtkwave tb_soc_stub_top.vcd

clean:
	rm -rf obj_dir *.vcd *.log
