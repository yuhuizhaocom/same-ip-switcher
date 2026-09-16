<#
    Network switch configuration (portable).
    All values are ASCII, safe for any system codepage.
    Put this file in the SAME folder as switch-network.ps1.
#>

# target static IPv4 for whichever adapter is active
$IpActive  = "10.2.5.199"

# subnet mask (255.255.248.0 = /21)
$Mask      = "255.255.248.0"

# default gateway
$Gw        = "10.2.3.254"

# DNS: 网关（$Gw）作为首选 DNS 自动应用，这里是备用公网 DNS（第 2 槽位）。
# 网卡只写 2 个 DNS（[网关, 备用]），因此不再配置第二公网 DNS。
$DnsPrimary   = "223.5.5.5"

# WiFi SSIDs to auto-connect, tried in order (first linked wins)
$WifiSsids = @("ENUO-12-5G", "ENUO-12")