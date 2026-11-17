import Foundation

private final class StalledWeatherRequest:URLProtocol {
    static let started=DispatchSemaphore(value:0)
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {Self.started.signal()}
    override func stopLoading() {}
}
private final class WeakWeatherFetch {
    weak var value:WeatherFetch?
    init(_ value:WeatherFetch) {self.value=value}
}

enum WeatherTests {
    static func run(_ check:@escaping(Bool,String)->Void) {
        let forecast:[String:Any]=[
            "utc_offset_seconds":28800,
            "current":["temperature_2m":12.4,"apparent_temperature":10.2,"relative_humidity_2m":45,"wind_direction_10m":90,"weather_code":2,"is_day":1,"wind_speed_10m":1.5,"wind_gusts_10m":2.8,"time":1790000000],
            "current_units":["wind_speed_10m":"m/s","wind_gusts_10m":"m/s"],
            "daily":["temperature_2m_min":[1,2,3],"temperature_2m_max":[15,16,17],"weather_code":[2,3,61],"precipitation_probability_max":[20,30,80],"uv_index_max":[3.1,NSNull(),1.0],"wind_speed_10m_max":[4.0,NSNull(),5.5]],
            "daily_units":["wind_speed_10m_max":"m/s"],
            "hourly":["time":(0..<12).map{1790000000+$0*3600},"temperature_2m":[Int](repeating:12,count:12),"precipitation_probability":[Int](repeating:20,count:12),"precipitation":[Double](repeating:0.1,count:12)]]
        let air:[String:Any]=["current":["pm2_5":24.1,"us_aqi":62],"current_units":["pm2_5":"μg/m³","us_aqi":"USAQI"]]
        let sample=WeatherCache.sample(forecast:forecast,air:air)!
        let current=sample["current"] as! [Any],days=sample["days"] as! [[Any]],hours=sample["hours"] as! [[Any]],a=sample["air"] as! [Int]
        check(current[0] as? Int==12 && current[6] as? Int==15 && current[7] as? Int==28,"weather cache Celsius, m/s tenths and rounding")
        check(days[0][4] as? Int==31 && days[1][4] is NSNull && hours.count==12 && hours[0][3] as? Int==1,"weather cache optional UV and hourly precipitation tenths")
        check(a==[241,62],"weather cache PM2.5 tenths and US AQI")
        var body:[String:Any]=["type":"weather.cache","id":UUID().uuidString,"device":"001122334455","client":UUID().uuidString,"token":String(repeating:"a",count:64),"latitude":-89.123456789,"longitude":-179.123456789,"city":String(repeating:"测",count:16),"sample":sample]
        check((try! JSONSerialization.data(withJSONObject:body)).count<=1536,"full weather packet fits the authenticated control envelope")
        check(WeatherCache.sample(forecast:[:],air:nil)==nil,"reject missing weather fields")
        var malformed=forecast;var c=forecast["current"] as! [String:Any];c["temperature_2m"]=true;malformed["current"]=c
        check(WeatherCache.sample(forecast:malformed,air:nil)==nil,"JSON booleans are not weather numbers")
        malformed=forecast;var h=forecast["hourly"] as! [String:Any];h["time"]=[1790000000,1790000000];malformed["hourly"]=h
        check(WeatherCache.sample(forecast:malformed,air:nil)==nil,"reject unordered weather timestamps")
        malformed=forecast;malformed["current_units"]=["wind_speed_10m":"knots"]
        check((WeatherCache.sample(forecast:malformed,air:nil)?["current"] as? [Any])?[6] is NSNull,"unknown wind units remain unavailable")
        body["sample"]=WeatherCache.sample(forecast:forecast,air:nil)
        check(WeatherCache.sample(forecast:forecast,air:nil)?["air"]==nil,"air failure preserves a usable forecast")
        let configuration=URLSessionConfiguration.ephemeral
        configuration.protocolClasses=[StalledWeatherRequest.self]
        let location=WeatherLocation(DeviceSettings())
        let cancelled=(0..<300).map { _ in autoreleasepool { ()->WeakWeatherFetch in
            let fetch=WeatherFetch(location:location,configuration:configuration) { _ in
                check(false,"cancelled weather request must not complete")
            }
            fetch.cancel();return WeakWeatherFetch(fetch)
        } }
        let deadline=Date().addingTimeInterval(5)
        while cancelled.contains(where:{$0.value != nil}) && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
        check(cancelled.allSatisfy{$0.value==nil},"300 immediate weather cancellations release every worker and session")
        while StalledWeatherRequest.started.wait(timeout:.now()) == .success {}
        var stalled:WeatherFetch?=WeatherFetch(location:location,configuration:configuration) { _ in
            check(false,"cancelled stalled weather request must not complete")
        }
        check(StalledWeatherRequest.started.wait(timeout:.now()+2) == .success,"weather request enters a stalled response")
        let released=WeakWeatherFetch(stalled!);stalled?.cancel();stalled=nil
        let cancelDeadline=Date().addingTimeInterval(2)
        while released.value != nil && Date()<cancelDeadline {Thread.sleep(forTimeInterval:0.01)}
        check(released.value==nil,"cancelled stalled weather response promptly releases its worker")
        print("Computer weather cache: units, bounds, optional values, malformed data and one-packet budget PASS")
        print("Weather cancellation: 300 immediate stops and stalled response cleanup PASS")
    }
}
