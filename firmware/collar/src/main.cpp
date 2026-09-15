#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <TinyGPSPlus.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "secrets.h"


// L76K GNSS Module for XIAO uses the XIAO hardware UART pins:
// XIAO D7 (GPIO44) <- GNSS TX
// XIAO D6 (GPIO43) -> GNSS RX
constexpr int GNSS_RX_PIN = D7;
constexpr int GNSS_TX_PIN = D6;
constexpr uint32_t GNSS_BAUD = 9600;
constexpr uint32_t ADDRESS_UPDATE_INTERVAL_MS = 60000;
constexpr double ADDRESS_UPDATE_DISTANCE_METERS = 50.0;
constexpr uint32_t SATELLITE_REPORT_INTERVAL_MS = 10000;
constexpr uint32_t SATELLITE_DATA_MAX_AGE_MS = 15000;
constexpr size_t MAX_TRACKED_SATELLITES = 64;
constexpr size_t NMEA_BUFFER_SIZE = 160;

TinyGPSPlus gps;
String currentAddress = "未取得";
double addressLatitude = 0.0;
double addressLongitude = 0.0;
uint32_t lastAddressUpdate = 0;
bool hasAddressPosition = false;

enum class Constellation : uint8_t {
  GPS,
  GLONASS,
  BEIDOU,
  QZSS,
  GALILEO,
  MIXED,
  UNKNOWN
};

struct SatelliteInfo {
  Constellation constellation = Constellation::UNKNOWN;
  uint16_t number = 0;
  int16_t elevationDegrees = -1;
  int16_t azimuthDegrees = -1;
  int16_t snrDbHz = -1;
  uint32_t lastSeenAt = 0;
  bool occupied = false;
};

SatelliteInfo satellites[MAX_TRACKED_SATELLITES];
char nmeaBuffer[NMEA_BUFFER_SIZE];
size_t nmeaLength = 0;
uint32_t lastSatelliteReport = 0;

const char *constellationName(Constellation constellation)
{
  switch (constellation) {
    case Constellation::GPS: return "GPS";
    case Constellation::GLONASS: return "GLONASS";
    case Constellation::BEIDOU: return "BeiDou";
    case Constellation::QZSS: return "QZSS";
    case Constellation::GALILEO: return "Galileo";
    case Constellation::MIXED: return "Mixed";
    default: return "Unknown";
  }
}

Constellation constellationFromNmea(const char *sentenceId, uint16_t satelliteNumber)
{
  if (strncmp(sentenceId, "GP", 2) == 0) {
    // QZSS is sometimes included in a GP sentence with PRN 193-202.
    return satelliteNumber >= 193 && satelliteNumber <= 202
               ? Constellation::QZSS
               : Constellation::GPS;
  }
  if (strncmp(sentenceId, "GL", 2) == 0) return Constellation::GLONASS;
  if (strncmp(sentenceId, "GB", 2) == 0 || strncmp(sentenceId, "BD", 2) == 0) {
    return Constellation::BEIDOU;
  }
  if (strncmp(sentenceId, "GQ", 2) == 0 || strncmp(sentenceId, "QZ", 2) == 0) {
    return Constellation::QZSS;
  }
  if (strncmp(sentenceId, "GA", 2) == 0) return Constellation::GALILEO;

  // A GN talker ID can contain satellites from multiple systems. These number
  // ranges are the common NMEA mappings; the receiver firmware may use a
  // different extended numbering scheme, so ambiguous entries remain Mixed.
  if (strncmp(sentenceId, "GN", 2) == 0) {
    if (satelliteNumber >= 1 && satelliteNumber <= 32) return Constellation::GPS;
    if (satelliteNumber >= 65 && satelliteNumber <= 96) return Constellation::GLONASS;
    if (satelliteNumber >= 193 && satelliteNumber <= 200) return Constellation::QZSS;
    if (satelliteNumber >= 201 && satelliteNumber <= 237) return Constellation::BEIDOU;
    return Constellation::MIXED;
  }
  return Constellation::UNKNOWN;
}

void updateSatellite(Constellation constellation, uint16_t number,
                     int16_t elevation, int16_t azimuth, int16_t snr)
{
  SatelliteInfo *emptySlot = nullptr;
  SatelliteInfo *oldestSlot = &satellites[0];

  for (SatelliteInfo &satellite : satellites) {
    if (satellite.occupied && satellite.constellation == constellation &&
        satellite.number == number) {
      satellite.elevationDegrees = elevation;
      satellite.azimuthDegrees = azimuth;
      satellite.snrDbHz = snr;
      satellite.lastSeenAt = millis();
      return;
    }
    if (!satellite.occupied && emptySlot == nullptr) emptySlot = &satellite;
    if (satellite.lastSeenAt < oldestSlot->lastSeenAt) oldestSlot = &satellite;
  }

  SatelliteInfo *target = emptySlot != nullptr ? emptySlot : oldestSlot;
  target->constellation = constellation;
  target->number = number;
  target->elevationDegrees = elevation;
  target->azimuthDegrees = azimuth;
  target->snrDbHz = snr;
  target->lastSeenAt = millis();
  target->occupied = true;
}

void parseGsvSentence(const char *sentence)
{
  char work[NMEA_BUFFER_SIZE];
  strncpy(work, sentence, sizeof(work) - 1);
  work[sizeof(work) - 1] = '\0';

  char *checksum = strchr(work, '*');
  if (checksum != nullptr) *checksum = '\0';

  char *fields[24];
  size_t fieldCount = 0;
  fields[fieldCount++] = work;
  for (char *cursor = work; *cursor != '\0' && fieldCount < 24; ++cursor) {
    if (*cursor == ',') {
      *cursor = '\0';
      fields[fieldCount++] = cursor + 1;
    }
  }

  const char *sentenceId = fields[0][0] == '$' ? fields[0] + 1 : fields[0];
  if (strlen(sentenceId) < 5 || strcmp(sentenceId + 2, "GSV") != 0 ||
      fieldCount < 8) {
    return;
  }

  // GSV fields repeat as: satellite number, elevation, azimuth, SNR.
  for (size_t index = 4; index + 3 < fieldCount; index += 4) {
    if (fields[index][0] == '\0') continue;
    const uint16_t number = static_cast<uint16_t>(atoi(fields[index]));
    if (number == 0) continue;

    const int16_t elevation = fields[index + 1][0] == '\0'
                                  ? -1 : static_cast<int16_t>(atoi(fields[index + 1]));
    const int16_t azimuth = fields[index + 2][0] == '\0'
                                ? -1 : static_cast<int16_t>(atoi(fields[index + 2]));
    const int16_t snr = fields[index + 3][0] == '\0'
                            ? -1 : static_cast<int16_t>(atoi(fields[index + 3]));
    updateSatellite(constellationFromNmea(sentenceId, number),
                    number, elevation, azimuth, snr);
  }
}

void collectNmeaCharacter(char character)
{
  if (character == '$') {
    nmeaLength = 0;
    nmeaBuffer[nmeaLength++] = character;
    return;
  }

  if (nmeaLength == 0) return;
  if (character == '\r' || character == '\n') {
    nmeaBuffer[nmeaLength] = '\0';
    parseGsvSentence(nmeaBuffer);
    nmeaLength = 0;
    return;
  }

  if (nmeaLength < sizeof(nmeaBuffer) - 1) {
    nmeaBuffer[nmeaLength++] = character;
  } else {
    nmeaLength = 0;
  }
}

const char *signalQuality(int16_t snr)
{
  if (snr < 0) return "未取得";
  if (snr >= 40) return "非常に強い";
  if (snr >= 30) return "良好";
  if (snr >= 20) return "弱め";
  return "非常に弱い";
}

const char *courseDirection(double degrees)
{
  static const char *directions[] = {
      "北", "北東", "東", "南東", "南", "南西", "西", "北西"};
  const int index = static_cast<int>((degrees + 22.5) / 45.0) % 8;
  return directions[index];
}

void printSatelliteReport()
{
  const uint32_t now = millis();
  size_t visibleCount = 0;
  size_t constellationCounts[7] = {};

  for (const SatelliteInfo &satellite : satellites) {
    if (satellite.occupied && now - satellite.lastSeenAt <= SATELLITE_DATA_MAX_AGE_MS) {
      visibleCount++;
      constellationCounts[static_cast<uint8_t>(satellite.constellation)]++;
    }
  }

  Serial.println();
  Serial.println("--- 受信中の衛星詳細（GSV） ---");
  Serial.printf("視野内の衛星: %u機 / 測位計算に使用: %lu機\n",
                static_cast<unsigned>(visibleCount), gps.satellites.value());
  Serial.print("内訳: ");
  for (uint8_t index = 0; index < 7; ++index) {
    if (constellationCounts[index] > 0) {
      Serial.printf("%s=%u  ", constellationName(static_cast<Constellation>(index)),
                    static_cast<unsigned>(constellationCounts[index]));
    }
  }
  Serial.println();
  Serial.println("種類      番号  仰角  方位角  SNR(dB-Hz)  信号状態");

  for (const SatelliteInfo &satellite : satellites) {
    if (!satellite.occupied || now - satellite.lastSeenAt > SATELLITE_DATA_MAX_AGE_MS) {
      continue;
    }
    Serial.printf("%-9s %4u  %4d  %6d  ", constellationName(satellite.constellation),
                  satellite.number, satellite.elevationDegrees, satellite.azimuthDegrees);
    if (satellite.snrDbHz >= 0) {
      Serial.printf("%10d  %s\n", satellite.snrDbHz,
                    signalQuality(satellite.snrDbHz));
    } else {
      Serial.printf("%10s  %s\n", "--", signalQuality(satellite.snrDbHz));
    }
  }
  Serial.println("※衛星には一般的な固有名がないため、衛星システム名と番号を表示します。");
  Serial.println();
}

bool isLeapYear(int year)
{
  return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

int daysInMonth(int year, int month)
{
  static const int days[] = {31, 28, 31, 30, 31, 30,
                             31, 31, 30, 31, 30, 31};
  if (month == 2 && isLeapYear(year)) {
    return 29;
  }
  return days[month - 1];
}

void printJapanTime()
{
  if (!gps.date.isValid() || !gps.time.isValid()) {
    Serial.println("日本時間  : 未取得");
    return;
  }

  int year = gps.date.year();
  int month = gps.date.month();
  int day = gps.date.day();
  int hour = gps.time.hour() + 9;

  if (hour >= 24) {
    hour -= 24;
    day++;
    if (day > daysInMonth(year, month)) {
      day = 1;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }

  Serial.printf("日本時間  : %04d-%02d-%02d %02d:%02d:%02d\n",
                year, month, day, hour,
                gps.time.minute(), gps.time.second());
}

String reverseGeocode(double latitude, double longitude)
{
  if (WiFi.status() != WL_CONNECTED) {
    return "Wi-Fi未接続のため住所を取得できません";
  }

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient https;
  String url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2"
               "&accept-language=ja&zoom=18&addressdetails=1&lat=";
  url += String(latitude, 6);
  url += "&lon=";
  url += String(longitude, 6);

  if (!https.begin(client, url)) {
    return "住所検索への接続に失敗しました";
  }

  https.addHeader("User-Agent", "Cowlog-GNSS-Prototype/1.0");
  https.addHeader("Accept-Language", "ja");
  const int responseCode = https.GET();

  String address;
  if (responseCode == HTTP_CODE_OK) {
    JsonDocument document;
    const DeserializationError error = deserializeJson(document, https.getStream());
    if (error) {
      address = "住所データの解析に失敗しました";
    } else {
      address = document["display_name"] | "住所が見つかりませんでした";
    }
  } else {
    address = "住所検索エラー HTTP ";
    address += responseCode;
  }

  https.end();
  return address;
}

void updateAddressIfNeeded(double latitude, double longitude)
{
  const bool firstLookup = !hasAddressPosition;
  const double movedMeters = firstLookup
                                 ? ADDRESS_UPDATE_DISTANCE_METERS
                                 : TinyGPSPlus::distanceBetween(
                                       addressLatitude, addressLongitude,
                                       latitude, longitude);
  const bool intervalElapsed =
      firstLookup || millis() - lastAddressUpdate >= ADDRESS_UPDATE_INTERVAL_MS;

  if (!intervalElapsed || (!firstLookup && movedMeters < ADDRESS_UPDATE_DISTANCE_METERS)) {
    return;
  }

  Serial.println("住所を検索しています...");
  currentAddress = reverseGeocode(latitude, longitude);
  addressLatitude = latitude;
  addressLongitude = longitude;
  lastAddressUpdate = millis();
  hasAddressPosition = true;
}

void printGnssData()
{
  Serial.println("--- GNSS fix ---");
  Serial.printf("Latitude : %.6f\n", gps.location.lat());
  Serial.printf("Longitude: %.6f\n", gps.location.lng());
  Serial.printf("Altitude : %.2f m\n", gps.altitude.meters());
  Serial.printf("Satellites used: %lu\n", gps.satellites.value());
  Serial.printf("HDOP     : %.2f（小さいほど衛星配置が良好）\n", gps.hdop.hdop());

  if (gps.speed.isValid()) {
    Serial.printf("Speed    : %.2f km/h\n", gps.speed.kmph());
  } else {
    Serial.println("Speed    : 未取得");
  }

  if (gps.course.isValid()) {
    Serial.printf("Course   : %.1f度（%s）\n",
                  gps.course.deg(), courseDirection(gps.course.deg()));
  } else {
    Serial.println("Course   : 未取得");
  }

  Serial.printf("位置データ経過時間: %lu ms\n", gps.location.age());
  printJapanTime();
  Serial.print("現在住所  : ");
  Serial.println(currentAddress);
}

void setup()
{
  Serial.begin(115200);
  delay(500);

  // HardwareSerial is more reliable than SoftwareSerial on ESP32-S3.
  Serial1.begin(GNSS_BAUD, SERIAL_8N1, GNSS_RX_PIN, GNSS_TX_PIN);

  Serial.println();
  Serial.println("L76K GNSS test");
  Serial.println("衛星詳細は10秒ごとに表示します。");

  Serial.print("Wi-Fiへ接続しています");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  const uint32_t wifiStartedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStartedAt < 20000) {
    delay(500);
    Serial.print('.');
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi connected: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("Wi-Fi接続に失敗しました。SSIDとパスワードを確認してください。");
    Serial.println("GNSS測位は続行しますが、住所表示にはWi-Fiが必要です。");
  }

  Serial.println("Waiting for a valid fix...");
  Serial.println("Keep the antenna connected and place it outdoors.");
}

void loop()
{
  while (Serial1.available() > 0) {
    const char character = static_cast<char>(Serial1.read());
    collectNmeaCharacter(character);

    if (gps.encode(character)) {
      if (gps.location.isValid()) {
        static uint32_t lastPrintedSecond = UINT32_MAX;
        const uint32_t currentSecond =
            gps.time.hour() * 3600UL + gps.time.minute() * 60UL + gps.time.second();
        if (gps.time.isValid() && currentSecond != lastPrintedSecond) {
          updateAddressIfNeeded(gps.location.lat(), gps.location.lng());
          printGnssData();
          lastPrintedSecond = currentSecond;
        }
      } else {
        static uint32_t lastFixMessage = 0;
        if (millis() - lastFixMessage >= 5000) {
          Serial.println("GNSS data received, but position is not fixed yet.");
          lastFixMessage = millis();
        }
      }
    }
  }

  if (millis() - lastSatelliteReport >= SATELLITE_REPORT_INTERVAL_MS) {
    printSatelliteReport();
    lastSatelliteReport = millis();
  }

  // A valid NMEA stream should arrive within a few seconds.
  static uint32_t lastWarning = 0;
  if (millis() > 5000 && gps.charsProcessed() < 10 &&
      millis() - lastWarning > 5000) {
    Serial.println("No GNSS data. Check the module direction and D6/D7 connection.");
    lastWarning = millis();
  }
}
