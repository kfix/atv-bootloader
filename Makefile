#!/usr/bin/make -f
.PHONY: clean
.NOTPARALLEL:
OSTYPE	= $(shell uname)
ARCH	:= i386
#AppleTV mkI uses 32-bit EFI 1.10

KERNEL ?= $(firstword $(wildcard boot/vmlinuz /boot/vmlinuz))
RAMDISK ?= $(firstword $(wildcard boot/initrd.img /boot/initrd.img))

DARWIN_IMAGE_BASE := 0x02000000

CC  ?= gcc
LLD ?= lld
override LLDFLAGS += -flavor darwin -arch $(ARCH) -macosx_version_min 10.4

export PATH := /usr/local/opt/llvm/bin:$(PATH)
#to use homebrew's llvm, prefix shell commands with env
override CC := env $(CC)
override LLD := env $(LLD)

#override CFLAGS += -arch $(ARCH) -fno-stack-protector -fno-builtin
override CFLAGS += --target=$(ARCH)-apple-darwin #target-triples http://clang.llvm.org/docs/CrossCompilation.html

CDIR    := $(shell if [ "$$PWD" != "" ]; then echo $$PWD; else pwd; fi)
TOPDIR  =
INCDIR  = -I. -I$(TOPDIR)

all: mach_kernel stick.img

$(SUBDIRS):
	$(MAKE) -C $@

# start.o must be 1st in the link order
BOOTOBJ	= start.o
OBJ = vsprintf.o console.o utils.o elilo_code.o darwin_code.o linux_code.o boot_loader.o
#OBJ += vgabios/vgabios.a
#OBJ += vgabios/x86emu/src/libx86emu.a
#SUBDIRS = vgabios

$(SUBDIRS):
	$(MAKE) -C $@

.c.o:
	$(CC) $(CFLAGS) -c -static -nostdlib -fno-stack-protector -o $@ -c $^

.s.o:
	$(CC) $(CFLAGS) -c -static -nostdlib -DASSEMBLER -o $@ -c $<

clean:
	rm -f *.o *.ol *.bc *.obj mach_kernel stick.img

# http://www.opensource.apple.com/source/xnu/xnu-3248.20.55/makedefs/MakeInc.def
mach_kernel: $(BOOTOBJ) $(OBJ)
	$(LLD) $(LLDFLAGS) \
	-t -static -e __start -no_pie -flat_namespace -undefined suppress \
	-version_load_command -function_starts \
	-o $@ $^ \
	-image_base $(DARWIN_IMAGE_BASE) \
	-sectalign __TEXT __text 0x1000 \
	-sectalign __DATA __common 0x1000 \
	-sectalign __DATA __bss 0x1000 \
	-sectcreate __TEXT __vmlinuz $(KERNEL) \
	-sectcreate __TEXT __initrd $(RAMDISK) \
	-sectcreate __PRELINK __text /dev/null \
	-sectcreate __PRELINK __symtab /dev/null \
	-sectcreate __PRELINK __info /dev/null

#bourne-shell version of http://wiki.osdev.org/Hdiutil ...
BOOTFILES = mach_kernel $(wildcard boot/* /boot/*)
BOOTBYTES = $(shell wc -c $(BOOTFILES) | awk 'END{print $$1}')
#BOOTBYTES != wc -c $(BOOTFILES) | awk 'END{print $$1}'
BOOTMEGS = $(shell echo $$[ ( $(BOOTBYTES) / 1024**2 ) + 2 ]  )
#BOOTBYTES := $(shell echo $$[ 257 * 1024**2 ] ) #mtools will not make fat32 smaller than 256mb, true minimum is 33Mib
SECSZ = 512 #newer USB sticks are 4096 block size, use hdparm -I to find out
BOOTSECTS = $(shell echo $$[ ( $(BOOTBYTES) / $(SECSZ) ) + $(SECSZ) ] )
BOOTSECTSALIGN = $(shell echo $$[ $(BOOTSECTS) - ( $(BOOTSECTS) % 63 ) ] )
FATGEOM = $(shell echo -T $(BOOTSECTSALIGN) -h 255 -s 63) #virtual CHS geometry

#https://code.google.com/p/atv-bootloader/wiki/PartitioningPatchstick
#https://code.google.com/p/atv-bootloader/wiki/AlternatePartitioning1
RECOFFSET := 40
RECSTARTBYTE = $(shell echo $$[ ( $(RECOFFSET) * $(SECSZ) ) ] )
#the appletv efi-rom expects the boot partition to start at 40s(s*512k), boot is much slower if not
stick.img: $(BOOTFILES)
	dd if=/dev/zero of=$@ bs=1m count=$(BOOTMEGS)
	@#should just prepend to recovery.fat
	sgdisk --clear $@
	sgdisk -a 1 -n 0:$(RECOFFSET):$$[$(BOOTSECTS)] -c 0:"Recovery" -t 0:af04 -i1 $@
	sgdisk -a 1 -n 0:$$[$(BOOTSECTS)+1]:$$[$(BOOTSECTS)+2] -c 0:"extrapart" -t 0:8300 -i2 $@ #af00 PATCHSTICK
	@#http://sourceforge.net/p/gptfdisk/code/ci/master/tree/gptcl.cc#l235 -N -E -f -F are broke for some reason
	mformat -v RECOVERY $(FATGEOM) -i $@@@$(RECOFFSET)s :: && \
		mcopy -s -i $@@@$(RECOFFSET)s $(BOOTFILES) :: || \
		(rm $@ && false)
	mdir -i $@@@$(RECOFFSET)s ::/
	@# http://www.gnu.org/software/mtools/manual/mtools.html#drive-letters @N[skmg] -> sects,KiB,MiB,GiB
	sgdisk -p $@
	@#should dd recovery.fat into RECOFFSET at this point
	@printf "\nTo flash a boot-stick for an AppleTV, run\n\t dd if=$@ of=/dev/stick bs=256k\n\t sgdisk -e /dev/stick\n"
	@echo To change the contents, run: 
	@printf "\tLinux: mount -t vfat -o loop,offset=$(RECSTARTBYTE) $@ /mnt/atv-stick\n"
	@printf "\tOSX: hdiutil attach stick.img -section $(RECOFFSET)\n"

NEWFSDOSGEOM = $(shell echo -s $(BOOTSECTSALIGN) -h 255 -u 63 -S $(SECSZ) -P $(SECSZ) -o $(RECOFFSET)) #virtual CHS geometry
recovery.fat: $(BOOTFILES)
	#https://github.com/danielhood/ddig
	dd if=/dev/zero of=$@ bs=$(SECSZ) count=$(BOOTSECTSALIGN)
	@case "$(OSTYPE)" in \
		Darwin) newfs_msdos -F 32 -v Recovery $(NEWFSDOSGEOM) ./$@ ;; \
		*) mformat -v RECOVERY $(FATGEOM) -i $@ :: ;; \
	esac
	#mcopy -s -i $@ $(BOOTFILES) :: || (rm $@ && false)
	mdir -i $@ ::/

recovery.hfs: $(BOOTFILES)
	#https://github.com/ahknight/hfsinspect
	dd if=/dev/zero of=$@ bs=$(SECSZ) count=$(BOOTSECTSALIGN)
	@case "$(OSTYPE)" in \
		Darwin)	newfs_hfs -N $(BOOTBYTES) -v Recovery -b $(SECSZ) ./$@ ;; \
		*) mkfs.hfsplus ;; \
	esac
	# https://github.com/detly/mactel-boot/blob/master/bless.c #hmm, uses linux ioctl
	# https://github.com/detly/mactel-boot-logo/blob/master/Makefile

recovery.dmg: $(BOOTFILES)
	#http://stackoverflow.com/questions/286419/how-to-build-a-dmg-mac-os-x-file-on-a-non-mac-platform
	#https://bugzilla.mozilla.org/show_bug.cgi?id=935237
	#these are ISO based DMGs, no HFS for aTV booting :-(
	genisoimage -V Recovery -D -R -apple -no-pad -o $@.iso $(BOOTFILES)
	dmg iso $@.iso $@

newfs_msdos:
	# netbsd: http://cvsweb.netbsd.org/bsdweb.cgi/src/sbin/newfs_msdos/?only_with_tag=MAIN
	# freebsd: https://svnweb.freebsd.org/base/head/sbin/newfs_msdos/newfs_msdos.c?view=markup
	# osx: http://www.opensource.apple.com/source/msdosfs/msdosfs-198/newfs_msdos.tproj/newfs_msdos.c
	# debian-kfreebsd: https://github.com/rbrito/pkg-hfsprogs/tree/master/debian/patches
	# android bionic: https://gitorious.org/android-enablement/system-core/source/master:toolbox/newfs_msdos.c
