@echo off
chcp 65001 > nul
title 貓咪大戰爭SeedTracker

echo 正在喚醒 Linux、從官方伺服器下載並本地編譯最新轉蛋池...
echo ---------------------------------------------------------
echo ⚠️ 注意：本地全自動解包需要下載與解密，耗時較長（約 1~2 分鐘)。

echo ☕ 請放著讓程式跑完，編譯完成後會自動為您開啟網頁！
echo.

:: 【第一階段】拔掉 start，讓批次檔在這裡「卡住」，直到編譯完全結束！
wsl bash -c "cd ~/battle-cats-rolls-local && env \$(cat .env | tr -d '\r' | xargs) ruby bin/build.rb tw"

echo.
echo ---------------------------------------------------------
echo ✅ 編譯完成！正在啟動伺服器...

:: 【第二階段】用 start 另開一個背景進程來跑伺服器 (這樣才不會卡住後面的開網頁指令)
start wsl bash -c "cd ~/battle-cats-rolls-local && bundle exec rackup -p 8080 -o 0.0.0.0"
 
:: 給伺服器 3 秒鐘的啟動暖機時間
timeout /t 3 /nobreak > NUL

:: 在最完美的時機打開瀏覽器！
start http://localhost:8080