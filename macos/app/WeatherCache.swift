import Foundation
import CoreFoundation

struct WeatherLocation:Equatable {
    let latitude:Double,longitude:Double,city:String
    init(_ settings:DeviceSettings) {latitude=settings.latitude;longitude=settings.longitude;city=settings.city}
}

enum WeatherCache {
    private static func number(_ value:Any?,_ low:Double,_ high:Double)->Double? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,(low...high).contains(n.doubleValue) else{return nil};return n.doubleValue
    }
    private static func required(_ value:Any?,_ low:Double,_ high:Double)throws->Int {
        guard let n=number(value,low,high) else{throw RadioFailure.message("天气数据不完整")};return Int(n.rounded())
    }
    private static func optional(_ value:Any?,_ high:Double,scale:Double=1)->Any {
        guard let n=number(value,0,high) else{return NSNull()};return Int((n*scale).rounded())
    }
    private static func wind(_ values:[String:Any],_ units:[String:Any],_ key:String)->Any {
        guard units[key] as? String=="m/s" else{return NSNull()};return optional(values[key],150,scale:10)
    }
    static func sample(forecast:[String:Any],air:[String:Any]?)->[String:Any]? {
        do {
            guard let c=forecast["current"] as? [String:Any],let d=forecast["daily"] as? [String:Any] else{return nil}
            let cu=forecast["current_units"] as? [String:Any] ?? [:],du=forecast["daily_units"] as? [String:Any] ?? [:]
            let current:[Any]=[
                try required(c["temperature_2m"],-90,65),try required(c["apparent_temperature"],-110,80),
                try required(c["relative_humidity_2m"],0,100),try required(c["wind_direction_10m"],0,360),
                try required(c["weather_code"],0,99),try required(c["is_day"],0,1),
                wind(c,cu,"wind_speed_10m"),wind(c,cu,"wind_gusts_10m"),
                try required(forecast["utc_offset_seconds"],-50400,50400),try required(c["time"],1700000000,2100000000)]
            func at(_ key:String,_ index:Int)->Any? {(d[key] as? [Any]).flatMap{index<$0.count ? $0[index]:nil}}
            var days=[[Any]]()
            for i in 0..<3 {
                let low=try required(at("temperature_2m_min",i),-90,65),high=try required(at("temperature_2m_max",i),-90,65)
                guard low<=high else{return nil}
                days.append([low,high,try required(at("weather_code",i),0,99),try required(at("precipitation_probability_max",i),0,100),optional(at("uv_index_max",i),50,scale:10),du["wind_speed_10m_max"] as? String=="m/s" ? optional(at("wind_speed_10m_max",i),150,scale:10):NSNull()])
            }
            let h=forecast["hourly"] as? [String:Any] ?? [:],times=h["time"] as? [Any] ?? []
            var hours=[[Any]](),previous=0
            func hour(_ key:String,_ index:Int)->Any? {(h[key] as? [Any]).flatMap{index<$0.count ? $0[index]:nil}}
            for i in 0..<min(12,times.count) {
                let time=try required(times[i],1700000000,2100000000);guard time>previous else{return nil};previous=time
                let temperature=number(hour("temperature_2m",i),-90,65).map{Int($0.rounded()) as Any} ?? NSNull()
                hours.append([time,temperature,optional(hour("precipitation_probability",i),100),optional(hour("precipitation",i),999,scale:10)])
            }
            var result:[String:Any]=["current":current,"days":days,"hours":hours]
            if let air=air,let ac=air["current"] as? [String:Any],let au=air["current_units"] as? [String:Any] {
                let pmUnit=au["pm2_5"] as? String ?? ""
                let pm:Any=["μg/m³","µg/m³","ug/m3"].contains(pmUnit) ? optional(ac["pm2_5"],10000,scale:10):NSNull()
                let aqi:Any=au["us_aqi"] as? String=="USAQI" ? optional(ac["us_aqi"],10000):NSNull()
                if !(pm is NSNull && aqi is NSNull) {result["air"]=[pm,aqi]}
            }
            return result
        } catch {return nil}
    }
}

/// Fetch on the computer so BLE-only devices do not need Internet/TLS memory.
/// One bounded, cancellable job; normal refresh is once every fifteen minutes.
final class WeatherFetch {
    private var task:Task<Void,Never>?
    private let network:URLSession
    init(location:WeatherLocation,configuration:URLSessionConfiguration = .ephemeral,completion:@escaping(Result<[String:Any],Error>)->Void) {
        configuration.timeoutIntervalForRequest=12;configuration.timeoutIntervalForResource=20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        network=URLSession(configuration:configuration)
        task=Task.detached(priority:.utility) { [self] in
            // The worker owns session invalidation, including cancellation.
            // A concurrent cancel must not invalidate before the next fetch.
            defer { network.invalidateAndCancel() }
            do {
                let coordinate=String(format:"latitude=%.4f&longitude=%.4f",locale:Locale(identifier:"en_US_POSIX"),location.latitude,location.longitude)
                let forecast=try await fetch("https://api.open-meteo.com/v1/forecast?"+coordinate+"&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,wind_speed_10m_max&hourly=temperature_2m,precipitation_probability,precipitation&forecast_days=3&forecast_hours=12&timezone=auto&timeformat=unixtime&wind_speed_unit=ms")
                let air=try? await fetch("https://air-quality-api.open-meteo.com/v1/air-quality?"+coordinate+"&current=pm2_5,us_aqi&forecast_days=1&timezone=auto")
                try Task.checkCancellation()
                guard let sample=WeatherCache.sample(forecast:forecast,air:air) else{throw RadioFailure.message("天气数据不完整")}
                completion(.success(sample))
            }catch{if !Task.isCancelled{completion(.failure(error))}}
        }
    }
    func cancel() {task?.cancel()}
    private func fetch(_ text:String)async throws->[String:Any] {
        try Task.checkCancellation()
        var request=URLRequest(url:URL(string:text)!);request.setValue(AppMetadata.userAgent,forHTTPHeaderField:"User-Agent")
        let (bytes,response)=try await network.bytes(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else{throw RadioFailure.message("天气服务暂不可用")}
        var data=Data()
        for try await byte in bytes {try Task.checkCancellation();guard data.count<32768 else{throw RadioFailure.message("天气数据超出范围")};data.append(byte)}
        guard let result=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw RadioFailure.message("天气数据格式不正确")};return result
    }
}
