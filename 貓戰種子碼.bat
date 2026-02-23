@echo off
chcp 65001 > nul
title 貓咪大戰爭預測伺服器 (自動更新版)

echo 正在喚醒 Linux、檢查最新轉蛋池...
echo ---------------------------------------------------------
echo 若檢查完畢，伺服器將自動啟動！


start wsl bash -c "cd ~/battle-cats-rolls && ruby bin/build.rb tw ; bundle exec rackup -p 8080 -o 0.0.0.0"


timeout /t 6 /nobreak > NUL


start http://localhost:8080