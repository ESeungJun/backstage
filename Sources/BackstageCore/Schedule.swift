import Foundation

let weekdayNames = ["일", "월", "화", "수", "목", "금", "토", "일"]

/// StartCalendarInterval 한 항목을 문장으로. launchd 에서 빠진 키는 와일드카드다.
public func describeCalendar(_ d: [String: Int]) -> String {
    let m = d["Minute"], h = d["Hour"], day = d["Day"], wd = d["Weekday"], mon = d["Month"]
    var when: String
    if let mon { when = "매년 \(mon)월 " + (day.map { "\($0)일" } ?? "매일") }
    else if let day { when = "매월 \(day)일" }
    else if let wd { when = "매주 \(weekdayNames[min(max(wd, 0), 7)])요일" }
    else { when = "매일" }
    if let h, let m { return "\(when) " + String(format: "%02d:%02d", h, m) }
    if let h { return "\(when) \(h)시대 매분" }   // Hour 만 있으면 그 시간 60분 내내 매분 돈다
    if let m { return (when == "매일" ? "" : when + " ") + "매시 \(m)분" }
    return (when == "매일" ? "" : when + " ") + "매분"
}

public func nextCalendarDate(_ d: [String: Int], after now: Date, calendar: Calendar = .current) -> Date? {
    var c = DateComponents()
    c.month = d["Month"]; c.day = d["Day"]; c.hour = d["Hour"]; c.minute = d["Minute"]
    if let wd = d["Weekday"] { c.weekday = (wd % 7) + 1 }   // launchd 0/7=일 → Calendar 1=일
    c.second = 0
    if c.minute == nil {
        // 분이 비어 있으면 매분이다. 바로 다음 분이 나머지 조건에 맞으면 그때 돈다.
        let secs = calendar.component(.second, from: now)
        let nextMinute = now.addingTimeInterval(Double(60 - secs)).addingTimeInterval(-now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1))
        let got = calendar.dateComponents([.month, .day, .hour, .weekday], from: nextMinute)
        let fits = (c.month == nil || c.month == got.month) && (c.day == nil || c.day == got.day)
            && (c.hour == nil || c.hour == got.hour) && (c.weekday == nil || c.weekday == got.weekday)
        if fits { return nextMinute }
        // 아니면 조건이 맞는 다음 구간의 첫 분
        c.minute = 0
        if c.hour == nil { c.hour = 0 }
    }
    return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
}

public func describeInterval(_ s: Int) -> String {
    if s % 86400 == 0 { return "\(s / 86400)일마다" }
    if s % 3600 == 0 { return "\(s / 3600)시간마다" }
    if s % 60 == 0 { return "\(s / 60)분마다" }
    return "\(s)초마다"
}
