import Foundation
import SwiftUI
import CoreLocation
import Combine

// MARK: - Weather Model & WMO Code Mapping

struct WeatherData: Codable {
    let current: CurrentWeather
    let hourly: HourlyWeather
}

struct CurrentWeather: Codable {
    let temperature_2m: Double
    let weather_code: Int
}

struct HourlyWeather: Codable {
    let time: [String]
    let temperature_2m: [Double]
    let weather_code: [Int]
}

// MARK: - WMO Weather Code to SF Symbol Mapper

enum WeatherCondition {
    case clear
    case mostlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm
    case unknown

    init(wmoCode: Int) {
        switch wmoCode {
        case 0:
            self = .clear
        case 1, 2, 3:
            self = .mostlyClear
        case 45, 48:
            self = .fog
        case 51, 52, 53, 54, 55, 56, 57:
            self = .drizzle
        case 61, 63, 65:
            self = .rain
        case 71, 73, 75, 77:
            self = .snow
        case 80, 81, 82:
            self = .showers
        case 95, 96, 99:
            self = .thunderstorm
        default:
            self = .unknown
        }
    }

    var sfSymbol: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .mostlyClear:
            return "cloud.sun.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
        case .overcast:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .showers:
            return "cloud.heavyrain.fill"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .clear:
            return "Clear"
        case .mostlyClear:
            return "Mostly Clear"
        case .partlyCloudy:
            return "Partly Cloudy"
        case .overcast:
            return "Overcast"
        case .fog:
            return "Fog"
        case .drizzle:
            return "Drizzle"
        case .rain:
            return "Rain"
        case .snow:
            return "Snow"
        case .showers:
            return "Showers"
        case .thunderstorm:
            return "Thunderstorm"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - Hourly Forecast Item

struct HourlyForecast {
    let hour: Int
    let tempC: Double
    let condition: String
    let wmoCode: Int
}

// MARK: - Weather Monitor (ObservableObject)

@MainActor
final class WeatherMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentTempC: Double = 0.0
    @Published var condition: String = "Loading"
    @Published var iconSF: String = "questionmark.circle.fill"
    @Published var nextHourForecast: [HourlyForecast] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date = Date()

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?
    private var refreshTimer: Timer?
    private var lastLocationCacheDate: Date?

    private let cacheKey = "com.sherpa.weatherlocation"
    private let cacheDateKey = "com.sherpa.weatherlocation.date"
    private let cacheExpiry: TimeInterval = 86400 // 24 hours

    override init() {
        super.init()
        setupLocationManager()
        loadCachedLocation()
        requestLocation()
        startRefreshTimer()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Location Manager Setup

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 1000 // 1km minimum change
    }

    private func requestLocation() {
        DispatchQueue.main.async {
            switch self.locationManager.authorizationStatus {
            case .notDetermined:
                self.locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationManager.startUpdatingLocation()
            case .denied, .restricted:
                // Use cached location or default
                if self.currentLocation == nil {
                    self.currentLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // SF default
                    self.fetchWeather()
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Location Caching

    private func loadCachedLocation() {
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
              let cachedDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date else {
            return
        }

        // Check if cache is still valid (24 hours)
        guard Date().timeIntervalSince(cachedDate) < cacheExpiry else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: cacheDateKey)
            return
        }

        if let location = try? JSONDecoder().decode(CachedLocation.self, from: cachedData) {
            currentLocation = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            lastLocationCacheDate = cachedDate
            fetchWeather()
        }
    }

    private func cacheLocation(_ location: CLLocationCoordinate2D) {
        let cached = CachedLocation(latitude: location.latitude, longitude: location.longitude)
        if let encoded = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheDateKey)
            lastLocationCacheDate = Date()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.cacheLocation(location.coordinate)
            self.fetchWeather()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Location error: \(error.localizedDescription)")
            // Fall back to cached or default
            if self.currentLocation == nil {
                self.currentLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                self.fetchWeather()
            }
        }
    }

    // MARK: - Weather API

    private func fetchWeather() {
        guard let location = currentLocation else { return }

        isLoading = true

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&forecast_days=1&timezone=auto"

        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }

                let decoder = JSONDecoder()
                let weatherData = try decoder.decode(WeatherData.self, from: data)

                await updateWeather(from: weatherData)
                lastUpdated = Date()
            } catch {
                print("Weather fetch error: \(error)")
            }

            isLoading = false
        }
    }

    // MARK: - Weather Update

    private func updateWeather(from data: WeatherData) {
        let condition = WeatherCondition(wmoCode: data.current.weather_code)

        currentTempC = data.current.temperature_2m
        self.condition = condition.description
        iconSF = condition.sfSymbol

        // Parse next 3 hourly forecasts
        var hourlyForecasts: [HourlyForecast] = []
        let formatter = ISO8601DateFormatter()

        if let currentDate = formatter.date(from: data.hourly.time[0]) {
            let calendar = Calendar.current
            var nextHours = Set<Int>()

            for i in 0..<min(24, data.hourly.time.count) {
                if let forecastDate = formatter.date(from: data.hourly.time[i]) {
                    let hourComponent = calendar.component(.hour, from: forecastDate)
                    let tempC = data.hourly.temperature_2m[i]
                    let wmoCode = data.hourly.weather_code[i]
                    let cond = WeatherCondition(wmoCode: wmoCode)

                    if forecastDate > currentDate && nextHours.count < 3 {
                        hourlyForecasts.append(
                            HourlyForecast(hour: hourComponent, tempC: tempC, condition: cond.description, wmoCode: wmoCode)
                        )
                        nextHours.insert(hourComponent)
                    }
                }
            }
        }

        nextHourForecast = hourlyForecasts
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchWeather()
            }
        }
    }
}

// MARK: - Cached Location Model

private struct CachedLocation: Codable {
    let latitude: Double
    let longitude: Double
}

// MARK: - SwiftUI Views

struct WeatherView: View {
    @StateObject private var monitor = WeatherMonitor()
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            // Liquid Glass Background
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.1),
                            Color.blue.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .background(.ultraThinMaterial)

            VStack(spacing: 8) {
                // Current Weather (Compact)
                HStack(spacing: 8) {
                    Image(systemName: monitor.iconSF)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(monitor.currentTempC, specifier: "%.1f")°C")
                            .font(.system(size: 16, weight: .semibold))
                        Text(monitor.condition)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if monitor.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Expanded Hourly Forecast
                if isExpanded && !monitor.nextHourForecast.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(spacing: 8) {
                        Text("Next 3 Hours")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)

                        HStack(spacing: 12) {
                            ForEach(monitor.nextHourForecast.prefix(3), id: \.hour) { forecast in
                                VStack(spacing: 6) {
                                    Text("\(forecast.hour):00")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    Image(systemName: WeatherCondition(wmoCode: forecast.wmoCode).sfSymbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.blue)

                                    Text("\(forecast.tempC, specifier: "%.0f")°")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 200)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Blur Effect (Compatibility)

struct BlurEffect: NSViewRepresentable {
    let style: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = style
        view.blendingMode = .withinWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = style
    }
}

// MARK: - Preview

/* DISABLED-PREVIEW #Preview {
    WeatherView()
        .padding()
        .frame(width: 300, height: 300)
} */
