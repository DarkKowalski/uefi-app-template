ARCH = x86_64
TARGET = efi-app-$(ARCH)

CC = clang
AS = clang
LD = ld.lld
RM = rm -fv
MKDIR = mkdir -p
OBJCOPY = objcopy # llvm-objcopy doesn't have this target
QEMU = qemu-system-$(ARCH)
GDB = gdb

# You should update this manually
EDK2_OVMF = OVMF.fd

# out of tree build
OUT_DIR = out
BUILD_DIR = build
SRC_DIRS = src
INC_DIRS = $(shell find $(SRC_DIRS) -type d)

SRCS = $(shell find $(SRC_DIRS) -name *.c)
INCS = $(addprefix -I,$(INC_DIRS))
OBJS = $(SRCS:%=$(BUILD_DIR)/%.o)
DEPS := $(OBJS:.o=.d)

EFI_HEADER_DIR = /usr/include/efi
EFI_LIB_DIR = /usr/lib

EFI_INCS = -I$(EFI_HEADER_DIR) \
		   -I$(EFI_HEADER_DIR)/$(ARCH) \
		   -I$(EFI_HEADER_DIR)/protocal
EFI_CRT_OBJS = $(EFI_LIB_DIR)/crt0-efi-$(ARCH).o
EFI_LDS = $(EFI_LIB_DIR)/elf_$(ARCH)_efi.lds

CFLAG_OPT = -O2 -flto
CFLAG_WARN = -Wall -Wextra
CFLAGS = $(INCS) \
		 $(EFI_INCS) \
		 $(CFLAG_WARN) \
		 $(CFLAG_OPT) \
		 -fno-stack-protector \
		 -fpic \
		 -fshort-wchar \
		 -mno-red-zone \
		 -MMD \
		 -MP
ifeq ($(ARCH),x86_64)
  CFLAGS += -DEFI_FUNCTION_WRAPPER
endif

LDFLAGS = -nostdlib \
		  -znocombreloc \
		  -T $(EFI_LDS) \
		  -shared \
		  -Bsymbolic \
		  -L $(EFI_LIB_DIR) \
		  $(EFI_CRT_OBJS) \
		  -lefi \
		  -lgnuefi

.PHONY: clean qemu qemu-gdb gdb debug

all: $(OUT_DIR)/$(TARGET).efi

qemu: $(OUT_DIR)/$(TARGET).efi
	$(QEMU) -drive file=$(EDK2_OVMF),format=raw,if=pflash \
			-enable-kvm \
			-boot menu=on \
			-kernel $^

qemu-gdb: $(OUT_DIR)/$(TARGET).efi
	$(QEMU) -drive file=$(EDK2_OVMF),format=raw,if=pflash \
			-enable-kvm \
			-boot menu=on \
			-kernel $^ \
			-S -gdb tcp::8899 &

gdb:
	$(GDB) -ex "target remote localhost:8899" $(OUT_DIR)/$(TARGET).efi

debug: qemu-gdb gdb

clean:
	$(RM) -r $(BUILD_DIR)

$(BUILD_DIR)/%.c.o: %.c
	$(MKDIR) $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/$(TARGET).so: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@

$(OUT_DIR)/$(TARGET).efi: $(BUILD_DIR)/$(TARGET).so
	$(MKDIR) $(OUT_DIR)
	$(OBJCOPY) -j .text \
		-j .sdata \
		-j .data \
		-j .dynamic \
		-j .dynsym \
		-j .rel \
		-j .rela \
		-j .reloc \
		--target=efi-app-$(ARCH) $^ $@
