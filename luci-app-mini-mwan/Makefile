# Copyright (C) 2024 Alex Schwartzman <openwrt@schwartzman.uk>
# This is free software, licensed under the GPL-2.0 license.

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for Mini-MWAN
LUCI_DESCRIPTION:=LuCI web interface for Mini-MWAN multi-WAN daemon
LUCI_DEPENDS:=+mini-mwan +luci-base

PKG_MAINTAINER:=Alex Schwartzman <openwrt@schwartzman.uk>
PKG_LICENSE:=GPL-2.0

# Standard LuCI makefile include - handles i18n compilation automatically
include ../../luci.mk

# vi: set noexpandtab tabstop=4 shiftwidth=4 :
# call BuildPackage - OpenWrt buildroot signature
