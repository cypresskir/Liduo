#!/bin/zsh
set -euo pipefail

echo 'Liduo — диагностика совместимости'
echo 'Модель Mac:'
/usr/sbin/sysctl -n hw.model
echo 'Версия macOS:'
/usr/bin/sw_vers -productVersion
echo 'Стандартный интерфейс угла крышки:'
/usr/bin/hidutil list --matching '{"VendorID":1452,"DeviceUsagePage":32,"DeviceUsage":138}'
echo 'Устройства Apple SPU 0x8104 (Product ID сам по себе не подтверждает датчик угла):'
/usr/bin/hidutil list --matching '{"VendorID":1452,"ProductID":33028}'
