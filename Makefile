include $(TOPDIR)/rules.mk

PKG_NAME:=mini-mwan
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/mini-mwan
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mini Multi-WAN management
  DEPENDS:=+lua +luci-base
  PKGARCH:=all
endef

define Package/mini-mwan/description
  Lightweight multi-WAN management with failover and load balancing.
  Features a modern JavaScript-based LuCI interface and Lua daemon.
endef

define Build/Compile
endef

define Package/mini-mwan/conffiles
/etc/config/mini-mwan
endef

define Package/mini-mwan/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/mini-mwan.lua $(1)/usr/bin/mini-mwan

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/mini-mwan.config $(1)/etc/config/mini-mwan

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/mini-mwan.init $(1)/etc/init.d/mini-mwan

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/mini-mwan
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mini-mwan/overview.js $(1)/www/luci-static/resources/view/mini-mwan/

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-mini-mwan.json $(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-mini-mwan.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,mini-mwan))
