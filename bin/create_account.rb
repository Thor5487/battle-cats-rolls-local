
require_relative '../lib/battle-cats-rolls/nyanko_auth'

auth = BattleCatsRolls::NyankoAuth.new
auth.inquiry_code = auth.generate_inquiry_code
puts "Inquiry code: #{auth.inquiry_code}"

auth.password = auth.generate_password
puts "Password: #{auth.password}"

jwt = auth.generate_jwt('999999')
puts "JWT: #{jwt}"
