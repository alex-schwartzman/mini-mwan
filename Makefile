include $(TOPDIR)/rules.mk

PKG_NAME:=mini-mwan
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/mini-mwan
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mini Multi-WAN management
  DEPENDS:=+ip +iptables
  PKGARCH:=all
endef

define Package/mini-mwan/description
  Mini Multi-WAN management application for OpenWRT
endef

define Build/Compile
endef

define Package/mini-mwan/conffiles
/etc/config/mini-mwan
endef

define Package/mini-mwan/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/mini-mwan.sh $(1)/usr/sbin/mini-mwan

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/mini-mwan.config $(1)/etc/config/mini-mwan

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/mini-mwan.init $(1)/etc/init.d/mini-mwan
endef

$(eval $(call BuildPackage,mini-mwan))
