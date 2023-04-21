
rack, = Rack::Builder.parse_file(
  File.expand_path("#{__dir__}/../config.ru"))

app :rack, rack, preload: true do
  listen(BattleCatsRolls::WebBind, reuseport: true)

  queue do
    worker_threads 5
  end
end

app :rack, rack, preload: true do
  listen(BattleCatsRolls::SeekBind, reuseport: true)

  queue do
    worker_threads 25
  end
end
