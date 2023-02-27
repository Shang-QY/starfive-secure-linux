sudo cp work/linux/arch/riscv/boot/Image /tftp
sudo cp work/linux/arch/riscv/boot/dts/starfive/jh7100-starfive-visionfive-v1.dtb /tftp/dtb.dtb
stat /tftp/Image
stat /tftp/dtb.dtb
