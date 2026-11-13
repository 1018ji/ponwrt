include $(TOPDIR)/rules.mk

PKG_NAME:=hg5585f-offload-tools
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/hg5585f-offload-tools
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=HG5585F passive NPU and WED checks
  DEPENDS:=@TARGET_airoha_an7581 +kmod-mt7915e +@PACKAGE_MAC80211_DEBUGFS
endef

define Package/hg5585f-offload-tools/description
  Read-only startup checks and bounded diagnostic collection for HG5585F
  NPU receive and WED transmit. Does not enable offload, generate traffic
  or trigger device recovery. Requires the matching offload_status driver.
endef

define Package/hg5585f-offload-tools/conffiles
/etc/config/hg5585f-offload-check
endef

define Build/Compile
endef

define Package/hg5585f-offload-tools/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/libexec $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) ./files/hg5585f-offload-check $(1)/usr/sbin/
	$(INSTALL_DATA) ./files/offload-report.awk $(1)/usr/libexec/hg5585f-offload-report.awk
	$(INSTALL_BIN) ./files/hg5585f-offload-check.init $(1)/etc/init.d/hg5585f-offload-check
	$(INSTALL_CONF) ./files/hg5585f-offload-check.config $(1)/etc/config/hg5585f-offload-check
endef

$(eval $(call BuildPackage,hg5585f-offload-tools))
