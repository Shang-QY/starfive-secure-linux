ISA ?= rv64imafdc
ABI ?= lp64d
TARGET_BOARD := U74
BOARD_FLAGS	:=
HWBOARD ?= visionfive

srcdir := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
srcdir := $(srcdir:/=)
confdir := $(srcdir)/conf
wrkdir := $(CURDIR)/work

buildroot_srcdir := $(srcdir)/buildroot
buildroot_initramfs_wrkdir := $(wrkdir)/buildroot_initramfs

# TODO: make RISCV be able to be set to alternate toolchain path
RISCV ?= $(buildroot_initramfs_wrkdir)/host
RVPATH ?= $(RISCV)/bin:/usr/sbin:/sbin:$(PATH)
target ?= riscv64-buildroot-linux-gnu

CROSS_COMPILE ?= $(RISCV)/bin/$(target)-

buildroot_initramfs_tar := $(buildroot_initramfs_wrkdir)/images/rootfs.tar
buildroot_initramfs_config := $(confdir)/buildroot_initramfs_config
buildroot_initramfs_sysroot_stamp := $(wrkdir)/.buildroot_initramfs_sysroot
buildroot_initramfs_sysroot := $(wrkdir)/buildroot_initramfs_sysroot
buildroot_rootfs_wrkdir := $(wrkdir)/buildroot_rootfs
buildroot_rootfs_ext := $(buildroot_rootfs_wrkdir)/images/rootfs.ext4
buildroot_rootfs_config := $(confdir)/buildroot_rootfs_config

linux_srcdir := $(srcdir)/linux
linux_wrkdir := $(wrkdir)/linux
linux_defconfig := $(confdir)/visionfive_defconfig

vmlinux := $(linux_wrkdir)/vmlinux
module_install_path:=$(wrkdir)/module_install_path
secure_linux := $(wrkdir)/sec-image
secure_dtb := $(wrkdir)/sec-dtb.dtb

initramfs := $(wrkdir)/initramfs.cpio.gz
rootfs := $(wrkdir)/rootfs.bin

target_gcc ?= $(CROSS_COMPILE)gcc

.PHONY: all check_arg
all: check_arg $(secure_linux)
	@echo
	@echo "This image has been generated for an ISA of $(ISA) and an ABI of $(ABI)"
	@echo "Find the image and DTB in work/sec-image and work/sec-dtb.dtb"
	@echo

check_arg:
ifeq ( , $(filter $(HWBOARD), starlight starlight-a1 visionfive))
	$(error board $(HWBOARD) is not supported, BOARD=[starlight | starlight-a1 | visionfive(deflault)])
endif

.PHONY: visionfive starlight starlight-a1

visionfive: HWBOARD := visionfive
visionfive: uboot_config := starfive_jh7100_visionfive_smode_defconfig
visionfive: uboot_dtb_file := $(wrkdir)/HiFive_U-Boot/arch/riscv/dts/jh7100-visionfive.dtb
visionfive: all

starlight: HWBOARD := starlight
starlight: uboot_config = starfive_jh7100_starlight_smode_defconfig
starlight: uboot_dtb_file = $(wrkdir)/HiFive_U-Boot/arch/riscv/dts/jh7100-beaglev-starlight.dtb
starlight: all

starlight-a1: HWBOARD := starlight-a1
starlight-a1: uboot_config = starfive_jh7100_starlight_smode_defconfig
starlight-a1: uboot_dtb_file = $(wrkdir)/HiFive_U-Boot/arch/riscv/dts/jh7100-beaglev-starlight-a1.dtb
starlight-a1: all

$(buildroot_initramfs_wrkdir)/.config: $(buildroot_srcdir)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_initramfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir) olddefconfig

# buildroot_initramfs provides gcc
$(buildroot_initramfs_tar): $(buildroot_srcdir) $(buildroot_initramfs_wrkdir)/.config $(buildroot_initramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir)

.PHONY: buildroot_initramfs-menuconfig
buildroot_initramfs-menuconfig: $(buildroot_initramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) savedefconfig
	cp $(dir $<)defconfig conf/buildroot_initramfs_config

# use buildroot_initramfs toolchain
# TODO: fix path and conf/buildroot_rootfs_config
$(buildroot_rootfs_wrkdir)/.config: $(buildroot_srcdir) $(buildroot_initramfs_tar)
#	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_rootfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(RVPATH) O=$(buildroot_rootfs_wrkdir) olddefconfig

$(buildroot_rootfs_ext): $(buildroot_srcdir) $(buildroot_rootfs_wrkdir)/.config $(target_gcc) $(buildroot_rootfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(RVPATH) O=$(buildroot_rootfs_wrkdir)
	cp -r $(module_install_path)/lib/modules $(buildroot_rootfs_wrkdir)/target/lib/

.PHONY: buildroot_rootfs
buildroot_rootfs: $(buildroot_rootfs_ext)
	cp $< $@

.PHONY: buildroot_rootfs-menuconfig
buildroot_rootfs-menuconfig: $(buildroot_rootfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_rootfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_rootfs_wrkdir) savedefconfig
	cp $(dir $<)defconfig conf/buildroot_rootfs_config

$(buildroot_initramfs_sysroot_stamp): $(buildroot_initramfs_tar)
	-rm -rf $(buildroot_initramfs_sysroot)
	mkdir -p $(buildroot_initramfs_sysroot)
	tar -xpf $< -C $(buildroot_initramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale
	touch $@

$(linux_wrkdir)/.config: $(linux_defconfig) $(linux_srcdir)
	mkdir -p $(dir $@)
	cp -p $< $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
ifeq (,$(filter rv%c,$(ISA)))
	sed 's/^.*CONFIG_RISCV_ISA_C.*$$/CONFIG_RISCV_ISA_C=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
endif
ifeq ($(ISA),$(filter rv32%,$(ISA)))
	sed 's/^.*CONFIG_ARCH_RV32I.*$$/CONFIG_ARCH_RV32I=y/' -i $@
	sed 's/^.*CONFIG_ARCH_RV64I.*$$/CONFIG_ARCH_RV64I=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
endif

$(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config $(target_gcc) $(buildroot_initramfs_sysroot)
	$(MAKE) -C $< O=$(linux_wrkdir) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PATH=$(RVPATH) \
		all \
		modules
	$(MAKE) -C $< O=$(linux_wrkdir) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PATH=$(RVPATH) \
		INSTALL_MOD_PATH=$(module_install_path) \
		modules_install

$(secure_linux): $(linux_srcdir) $(linux_wrkdir)/.config $(target_gcc) $(buildroot_initramfs_sysroot) $(initramfs)
	$(MAKE) -C $< O=$(linux_wrkdir) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		CONFIG_INITRAMFS_SOURCE=$(initramfs) \
		PATH=$(RVPATH) \
		vmlinux		\
		all
	cp $(linux_wrkdir)/arch/riscv/boot/Image $(secure_linux)
	cp $(linux_wrkdir)/arch/riscv/boot/dts/starfive/jh7100-starfive-visionfive-v1.dtb $(secure_dtb)

# vpu building depend on the $(vmlinux), $(vmlinux) depend on $(buildroot_initramfs_sysroot)
# so vpubuild should be built seperately
vpubuild: $(vmlinux) wave511-build wave521-build codaj12-build omxil-build gstomx-build vpudriver-build
wave511-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave511-dirclean
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave511-rebuild
wave521-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave521-dirclean
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave521-rebuild
codaj12-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) codaj12-dirclean
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) codaj12-rebuild
omxil-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) sf-omx-il-dirclean
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) sf-omx-il-rebuild
gstomx-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) sf-gst-omx-dirclean
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) sf-gst-omx-rebuild
vpudriver-build:
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave511driver
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) wave521driver
	$(MAKE) -C $(buildroot_initramfs_wrkdir) O=$(buildroot_initramfs_wrkdir) codaj12driver

vpubuild_rootfs: $(vmlinux) wave511-build-rootfs wave521-build-rootfs codaj12-build-rootfs omxil-build-rootfs gstomx-build-rootfs vpudriver-build-rootfs
wave511-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave511-dirclean
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave511-rebuild
wave521-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave521-dirclean
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave521-rebuild
codaj12-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) codaj12-dirclean
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) codaj12-rebuild
omxil-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) sf-omx-il-dirclean
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) sf-omx-il-rebuild
gstomx-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) sf-gst-omx-dirclean
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) sf-gst-omx-rebuild
vpudriver-build-rootfs:
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave511driver
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) wave521driver
	$(MAKE) -C $(buildroot_rootfs_wrkdir) O=$(buildroot_rootfs_wrkdir) codaj12driver


.PHONY: initrd
initrd: $(initramfs)

initramfs_cpio := $(wrkdir)/initramfs.cpio

$(initramfs).d: $(buildroot_initramfs_sysroot) $(buildroot_initramfs_tar)
	touch $@

$(initramfs): $(buildroot_initramfs_sysroot) $(vmlinux) $(buildroot_initramfs_tar)
	cp -r $(module_install_path)/lib/modules $(buildroot_initramfs_sysroot)/lib/
	cd $(linux_wrkdir) && \
		$(linux_srcdir)/usr/gen_initramfs.sh \
		-l $(initramfs).d \
		-o $(initramfs_cpio) -u $(shell id -u) -g $(shell id -g) \
		$(confdir)/initramfs.txt \
		$(buildroot_initramfs_sysroot)
	@(cat $(initramfs_cpio) | gzip -n -9 -f - > $@) || (rm -f $@; echo "Error: Fail to compress $(initramfs_cpio)"; exit 1)
	@rm -f $(initramfs_cpio)

.PHONY: linux-menuconfig
linux-menuconfig: $(linux_wrkdir)/.config
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) menuconfig
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) savedefconfig
	cp $(dir $<)defconfig $(linux_defconfig)

$(rootfs): $(buildroot_rootfs_ext)
	cp $< $@

$(buildroot_initramfs_sysroot): $(buildroot_initramfs_sysroot_stamp)

.PHONY: buildroot_initramfs_sysroot vmlinux
buildroot_initramfs_sysroot: $(buildroot_initramfs_sysroot)
vmlinux: $(vmlinux)

.PHONY: clean
clean:
	rm work/initramfs.cpio.gz
	rm work/linux/vmlinux
	rm work/sec-image
	rm work/sec-dtb.dtb
ifeq ($(buildroot_rootfs_ext),$(wildcard $(buildroot_rootfs_ext)))
	rm work/buildroot_rootfs/images/rootfs.ext4
endif
ifeq ($(buildroot_initramfs_tar),$(wildcard $(buildroot_initramfs_tar)))
	rm work/buildroot_initramfs/images/rootfs.tar
	rm -rf work/buildroot_initramfs/target/root/penglai_rootfs
endif

.PHONY: distclean
distclean:
	rm -rf -- $(wrkdir) $(toolchain_dest)
