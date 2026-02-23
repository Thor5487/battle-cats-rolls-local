# 貓咪大戰爭預測伺服器 - 從零開始架設指南

本指南將帶領你從一台全新的 Windows 電腦開始，透過 WSL2 (Windows Subsystem for Linux) 打造專屬的《貓咪大戰爭》本地端預測伺服器。

---

## 階段一：系統環境準備 (Windows WSL2)

若你的 Windows 尚未安裝 Linux 子系統，請依照以下步驟啟用：

對著 Windows 的「開始」按鈕點擊右鍵，選擇 **「終端機 (系統管理員)」** 或 **「Windows PowerShell (系統管理員)」**。
輸入以下指令並按下 Enter：

    wsl --install
重新啟動電腦 以完成安裝。

重開機後，開啟 Ubuntu 應用程式，並依照畫面提示設定你的 UNIX 帳號名稱與密碼（輸入密碼時畫面不會顯示字元，直接輸入完按 Enter 即可）。

階段二：基礎開發環境建置 (Ubuntu)
進入 Ubuntu 終端機後，我們需要安裝 Ruby 語言及相關的編譯工具。

更新系統軟體清單：

    sudo apt update && sudo apt upgrade -y
安裝核心工具與依賴套件 (包含 Git、Ruby 與底層 C 語言編譯工具)：
    
    sudo apt install -y git ruby-full build-essential patch zlib1g-dev liblzma-dev libicu-dev clang
階段三：專案安裝與設定
環境打底完成後，接著將專案原始碼下載到本地並安裝套件。

將專案 Clone 到本地 (請將網址替換為你自己的 GitHub 倉庫網址)：
    
    git clone https://github.com/Thor5487/battle-cats-rolls-local
進入專案資料夾：
    
    cd battle-cats-rolls-local
安裝 Ruby 專屬套件管理員 (Bundler)：
    
    sudo gem install bundler

安裝所有專案所需套件 (根據 Gemfile 自動下載)：
    
    bundle config set --local path 'vendor/bundle'
    bundle install
    ./Seeker/bin/build-VampireFlower.sh
    ./Seeker/bin/build-8.6.sh
階段四：建置遊戲資料庫與啟動伺服器
最後一步，抓取最新的轉蛋池資料並啟動你的伺服器！

下載並解析台版 (BCTW) 轉蛋資料：
    
    ruby bin/build.rb tw
啟動伺服器：
方法一:
    
    bundle exec rackup -p 8080 -o 0.0.0.0
方法二:
將"貓戰種子碼.bat"移至桌面上，點開即可。

當終端機顯示 Rackup::Handler::WEBrick::Server#start 且沒有報錯時，恭喜你架設成功！
請打開瀏覽器前往 👉 http://localhost:8080 即可開始使用。
