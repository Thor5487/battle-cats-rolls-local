require_relative 'lib/battle-cats-rolls/nyanko_auth'

puts "正在向官方伺服器註冊全新的虛擬免洗帳號..."

# 1. 召喚警衛 (此時還沒有帳號密碼)
auth = BattleCatsRolls::NyankoAuth.new

# 2. 向官方申請一個全新的詢問碼 (Inquiry Code)
new_code = auth.generate_inquiry_code
auth.inquiry_code = new_code
puts "✅ 成功取得新詢問碼: #{new_code}"

# 3. 用這個新詢問碼，向官方申請對應的隱藏密碼 (Password)
new_password = auth.generate_password
puts "✅ 成功取得專屬密碼: #{new_password}"

puts "\n=== 請將以下內容複製，貼到你的 .env 檔案中 ==="
puts "INQUIRY_CODE=#{new_code}"
puts "PASSWORD=#{new_password}"
