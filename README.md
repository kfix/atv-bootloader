atv-bootloader 1.0
====
Spork of [atv-bootloader](http://github.com/sdavilla/atv-bootloader) w/LLD build tooling.
[Original author's notes](README).
Original GPLv2 [license](COPYING) applies.

Requirements
---
- LLD 3.8+: LLVM's cross-platform multi-format [linker](http://lld.llvm.org/design.html)
  *  OSX: brew install llvm --HEAD --with-lld --with-clang
  *  Debian: ask sledru to add lld to http://llvm.org/apt
     * http://anonscm.debian.org/viewvc/pkg-llvm/llvm-toolchain/branches/
     * https://packages.qa.debian.org/l/llvm-toolchain-3.8.html
     * https://packages.qa.debian.org/l/llvm-toolchain-snapshot.html
- GNU Make
- [gptfdisk](https://sourceforge.net/p/gptfdisk/code/ci/master/tree/) & mtools (to make USB images)
  * OSX: brew install gptfdisk mtools
  * Debian: #apt-get install gdisk mtools

- `vmlinuz` & `initrd.img` files in `/boot` or in this project folder

Building
---
* `make mach_kernel`

Booting
---
If you are building from the AppleTV, just run `make install` to stage the mach_kernel to /boot,
assuming that /boot is a leading HFS partition on the drive.

You also need some files in /boot to satisfy AppleTV's EFI:  
  * boot.efi
    - the much maligned checksummed EFI stage1.
  * com.apple.Boot.plist
    - config file for the EFI's Mach-O loader.
  * BootLogo.png
    - Splash logo shown by the EFI loader on power up.

If you are not compiling from the Apple TV, you need to make a boot image with `make stick.img`.  
All needed files will be put on the image's boot partitions, set up according to ATV's quirky rules.  
A command will be printed that can be used to flash the image to a USB stick.

Why 1.0?
---
Not much has changed in the actual bootloader code from 2008, but 10 years  
of LLVM development allows us to now build simple Mach-O binaries from Linux!  

So the big anti-feature of 1.0 is to *not* ship a precompiled `/mach_kernel`!
Instead, lld makes it quick and easy to build one at any time from whatever kernel & initrd  
your Linux distro's installer or package manager provides. That way, you can always boot  
up-to-date Linux kernels with out any kexec nonsense.

Why now?
---
ATV1 is now in the "vintage computing" genre, but the hardware was ahead of its day.
However the OSX 10.4-lite that it shipped with is now obsolete.  

The lack of hardware 1080 MPEG4 decoding makes ATV1 worse than a RasPi for home media. 

I used atv-bootloader since 2009 to run Linux as a headlesss server, but even with  
the "patchstick" it was not easy to get post-2009 Linux 3.0+ distributions installed and running.  

Maybe [Swift](https://github.com/apple/swift) & its [Foundation frameworks] (https://github.com/apple/swift-corelibs-foundation) can be run on  
[PureDarwin](https://github.com/PureDarwin/PureDarwin) to make ATV1 the first sans-ObjC Hackintosh.

What's next?
---
- Finish sdavilla's work on shimming vgabios so Linux will see a standard Nvidia GPU and  
  control it normally without needing [hacky atv-linux quirks](appletv_nouveau_component_video.patch) in the mainline drivers.
  - see vgabios.patch for the gory details
- Shim up AppleTV's pre-UEFI env to natively support modern EFI-mode Linux.
- Support [bootstrapping Multiboot kernels](https://github.com/stv0g/xhyve/commit/59c43a3b848190f97d11a2dd2ce64f212a89c4ed) instead of vmlinuz.
  - Like Grub2's core.img -- grub-efi or grub-pc platform? BOOT ALL THE THINGS!

Code layout
---
* start.s
  - `__start` trampoline
* boot_loader.c
  - main routine
* darwin_code.c
  - finds the Mach-O segments holding the linux kernel assets in `/mach_kernel`
* linux_code.c
  - fixes up some fake PC-BIOS memory maps to make Linux think this is a plain PC.


