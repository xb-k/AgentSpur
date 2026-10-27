#!/usr/bin/env bash
cd "$(dirname "$0")"
chmod +x ./build_dmg.sh
./build_dmg.sh
echo ""
read -n 1 -s -r -p "按任意键关闭此窗口..."
echo ""
