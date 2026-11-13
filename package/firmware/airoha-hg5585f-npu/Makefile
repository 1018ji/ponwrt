include $(TOPDIR)/rules.mk

PKG_NAME:=airoha-hg5585f-npu-firmware
PKG_RELEASE:=1
PKG_LICENSE:=Proprietary
PKG_FILE_DEPENDS:=$(CURDIR)/files

include $(INCLUDE_DIR)/package.mk

define Package/airoha-hg5585f-npu-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=HG5585F 2024 NPU WLAN firmware
  DEPENDS:=@TARGET_airoha_an7581
endef

define Package/airoha-hg5585f-npu-firmware/description
  Locally extracted HG5585F NPU firmware. Requires the experimental legacy
  protocol patch and an explicit device-tree overlay. This firmware has no
  verified upstream PPE ABI and is not selected by default.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	@test -r ./files/npu_rv32.bin -a -r ./files/npu_data.bin || { \
		echo "Missing stock firmware: place verified npu_rv32.bin and npu_data.bin in package/firmware/airoha-hg5585f-npu/files/" >&2; \
		exit 1; \
	}
	@$(MKHASH) sha256 ./files/npu_rv32.bin | \
		grep -qx a8757aabc872c31d20683aeb4c05dbb9f7f590bdd6a1102c8a6902385bb5e9a6
	@$(MKHASH) sha256 ./files/npu_data.bin | \
		grep -qx 6f8cd8d7cd1cdaadfa03bef63bf71c1ad21aa2a4ad950b501761d2387d52a696
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/airoha-hg5585f-npu-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/airoha
	$(INSTALL_DATA) ./files/npu_rv32.bin $(1)/lib/firmware/airoha/hg5585f_npu_rv32.bin
	$(INSTALL_DATA) ./files/npu_data.bin $(1)/lib/firmware/airoha/hg5585f_npu_data.bin
endef

$(eval $(call BuildPackage,airoha-hg5585f-npu-firmware))
