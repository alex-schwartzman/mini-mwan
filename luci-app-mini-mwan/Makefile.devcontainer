include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mini-mwan
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Alex Schwartzman <openwrt@schwartzman.uk>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mini-mwan
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Mini-MWAN
  DEPENDS:=+mini-mwan +luci-base
  PKGARCH:=all
endef

define Package/luci-app-mini-mwan/description
  LuCI web interface for Mini-MWAN multi-WAN daemon.
  Provides status monitoring and configuration management through the OpenWrt web interface.
endef

define Build/Compile
endef

define Package/luci-app-mini-mwan/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/mini-mwan
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mini-mwan/status.js \
		$(1)/www/luci-static/resources/view/mini-mwan/status.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mini-mwan/overview.js \
		$(1)/www/luci-static/resources/view/mini-mwan/overview.js

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-mini-mwan.json \
		$(1)/usr/share/luci/menu.d/luci-app-mini-mwan.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-mini-mwan.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-mini-mwan.json
endef

$(eval $(call BuildPackage,luci-app-mini-mwan))
