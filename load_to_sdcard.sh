if test -e /dev/sda4
then
    sudo mount /dev/sda4 /media/sqy/__
    sudo rm /media/sqy/__/home/riscv/new_sec/Image
    sudo rm /media/sqy/__/home/riscv/new_sec/dtb.dtb
    sudo cp work/linux/arch/riscv/boot/Image /media/sqy/__/home/riscv/new_sec/
    sudo cp work/linux/arch/riscv/boot/dts/starfive/jh7100-starfive-visionfive-v1.dtb /media/sqy/__/home/riscv/new_sec/dtb.dtb
    echo 'stat Image'
    sudo stat /media/sqy/__/home/riscv/new_sec/Image
    echo 'stat dtb.dtb'
    sudo stat /media/sqy/__/home/riscv/new_sec/dtb.dtb
    sudo sync
    sudo umount /media/sqy/__/
    echo 'Transfer successfully!'
else
    echo 'Device not found!'
fi
