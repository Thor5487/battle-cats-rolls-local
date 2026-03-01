@echo off
chcp 65001 > nul
title 貓咪大戰爭預測伺服器 (大神同步版)

echo 正在喚醒 Linux、從大神的資料庫同步最新轉蛋池...
echo ---------------------------------------------------------
echo 若同步完畢，伺服器將自動啟動！

:: 核心修改區：拿掉 build.rb，換成 git fetch 和 git checkout
start wsl bash -c "cd ~/battle-cats-rolls && git fetch upstream && git checkout upstream/master -- build/ && bundle exec rackup -p 8080 -o 0.0.0.0"

timeout /t 6 /nobreak > NUL

start http://localhost:8080